import CoreML
import FluidAudio
import Foundation

/// The supported first local model: Parakeet TDT 0.6B v3, INT8 Core ML export.
/// Installation may access the network; validation and recognition never do.
nonisolated enum ParakeetModelFiles {
    static let repositoryFolderName = Repo.parakeetV3.folderName
    static let downloadSizeDescription = "About 500 MB"
    static let requiredNames = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    static func validate(at directory: URL) throws {
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else {
            throw ParakeetRuntimeError.invalidModelFolder
        }

        for name in requiredNames where name.hasSuffix(".mlmodelc") {
            let bundle = directory.appendingPathComponent(name, isDirectory: true)
            guard let bundleValues = try? bundle.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  bundleValues.isDirectory == true, bundleValues.isSymbolicLink != true else {
                throw ParakeetRuntimeError.incompleteModel(name)
            }
            let weights = bundle.appendingPathComponent("weights", isDirectory: true)
            guard let weightValues = try? weights.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  weightValues.isDirectory == true, weightValues.isSymbolicLink != true else {
                throw ParakeetRuntimeError.incompleteModel("\(name)/weights")
            }
            // These compiled-model payloads must be present, not just empty bundle folders
            // or Git LFS pointer files copied from a repository checkout.
            for component in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                try validateFile(bundle.appendingPathComponent(component), name: "\(name)/\(component)")
            }
        }
        _ = try vocabulary(at: directory)
    }

    /// Downloads into an isolated repository folder, then installs into exactly `directory`.
    /// FluidAudio otherwise rewrites the last path component to its repository name.
    static func download(to directory: URL) async throws {
        let fileManager = FileManager.default
        try checkEmptyDestination(directory)
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Sayso-Parakeet-\(UUID().uuidString)", isDirectory: true)
        let repository = stagingRoot.appendingPathComponent(repositoryFolderName, isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try Task.checkCancellation()
        let downloaded = try await AsrModels.download(to: repository, version: .v3, encoderPrecision: .int8)
        try Task.checkCancellation()
        try validate(at: downloaded)
        try checkEmptyDestination(directory)
        try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.moveItem(at: downloaded, to: directory)
    }

    fileprivate static func vocabulary(at directory: URL) throws -> [Int: String] {
        let url = directory.appendingPathComponent("parakeet_vocab.json")
        try validateFile(url, name: "parakeet_vocab.json")
        let data = try Data(contentsOf: url)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [String: String],
              entries.count == 8_192 else {
            throw ParakeetRuntimeError.invalidVocabulary
        }
        var vocabulary: [Int: String] = [:]
        for tokenID in 0..<8_192 {
            guard let token = entries[String(tokenID)] else {
                throw ParakeetRuntimeError.invalidVocabulary
            }
            vocabulary[tokenID] = token
        }
        return vocabulary
    }

    private static func validateFile(_ url: URL, name: String) throws {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else {
            throw ParakeetRuntimeError.incompleteModel(name)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 128) ?? Data()
        if String(decoding: prefix, as: UTF8.self).hasPrefix("version https://git-lfs.github.com/spec/") {
            throw ParakeetRuntimeError.incompleteModel(name)
        }
    }

    private static func checkEmptyDestination(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw ParakeetRuntimeError.destinationExists
        }
    }
}

/// Loads only explicitly installed local files. Do not use AsrModels.load here:
/// its ModelHub recovery path may delete and download a model after a load failure.
actor ParakeetRuntime: ParakeetRecognizing {
    private let directory: URL
    private var manager: AsrManager?

    init(directory: URL) {
        self.directory = directory
    }

    func prepare() async throws {
        guard manager == nil else { return }
        try Task.checkCancellation()
        try ParakeetModelFiles.validate(at: directory)
        let vocabulary = try ParakeetModelFiles.vocabulary(at: directory)
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #else
        configuration.computeUnits = .cpuAndNeuralEngine
        #endif
        let computeUnits = configuration.computeUnits
        let preprocessor = try await load("Preprocessor.mlmodelc", computeUnits: .cpuOnly)
        let encoder = try await load("Encoder.mlmodelc", computeUnits: computeUnits)
        let decoder = try await load("Decoder.mlmodelc", computeUnits: computeUnits)
        let joint = try await load("JointDecisionv3.mlmodelc", computeUnits: computeUnits)
        let models = AsrModels(
            encoder: encoder,
            preprocessor: preprocessor,
            decoder: decoder,
            joint: joint,
            configuration: configuration,
            vocabulary: vocabulary,
            version: .v3
        )
        let preparedManager = AsrManager(config: .default)
        try await preparedManager.loadModels(models)
        try Task.checkCancellation()
        manager = preparedManager
    }

    /// `samples` must be mono, 16 kHz, Float32 PCM, normalized to [-1, 1].
    func transcribe(_ samples: [Float]) async throws -> String {
        try Task.checkCancellation()
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else {
            throw ParakeetRuntimeError.invalidAudio
        }
        try await prepare()
        guard let manager else { throw ParakeetRuntimeError.modelNotLoaded }
        // A fresh decoder state prevents independent recordings influencing each other.
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state)
        try Task.checkCancellation()
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load(_ name: String, computeUnits: MLComputeUnits) async throws -> MLModel {
        try Task.checkCancellation()
        // Transfer a fresh configuration to Core ML for each asynchronous load.
        // MLModelConfiguration is mutable and must not be shared across actor boundaries.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        return try await MLModel.load(contentsOf: directory.appendingPathComponent(name), configuration: configuration)
    }
}

nonisolated enum ParakeetRuntimeError: LocalizedError {
    case invalidModelFolder
    case incompleteModel(String)
    case invalidVocabulary
    case destinationExists
    case invalidAudio
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .invalidModelFolder:
            "Choose a folder containing the Parakeet TDT v3 Core ML model files."
        case .incompleteModel(let name):
            "The local Parakeet model is incomplete: \(name). Download the model again or import the complete folder."
        case .invalidVocabulary:
            "This vocabulary does not match Parakeet TDT v3. Import the v3 model folder with its original parakeet_vocab.json."
        case .destinationExists:
            "The model installation folder is already in use."
        case .invalidAudio:
            "The recording contains no usable audio."
        case .modelNotLoaded:
            "Load the local Parakeet model before recording."
        }
    }
}
