# Local Parakeet transcription

Sayso’s first non-Apple speech backend is **NVIDIA Parakeet TDT 0.6B v3**, using Fluid Inference’s INT8 Core ML export. **Apple Speech remains the default.** Users can choose Parakeet when they want a custom local model; no provider fallback runs automatically. Parakeet converts speech into text. Writing styles still use Apple Intelligence; Original does not.

## Setup

1. Tap the speech model label on Home, or open Settings.
2. Change Speech model from Apple Speech to **Parakeet · local**.
3. Choose **Download Parakeet** (about 500 MB, from Hugging Face), or **Import model folder** to copy an existing Core ML export from Files.
4. Choose Original and record, then Stop. The transcript appears after processing.

The import folder must contain these items directly, not inside a second repository folder:

```text
Preprocessor.mlmodelc/
Encoder.mlmodelc/
Decoder.mlmodelc/
JointDecisionv3.mlmodelc/
parakeet_vocab.json
```

Use the actual compiled model files from [Fluid Inference’s v3 model repository](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). Git LFS pointer files, empty bundles, incomplete downloads and mismatched vocabulary are rejected. Arbitrary ONNX, NeMo and MLX model files are not supported. Folder validation checks completeness; Core ML compatibility is checked when the model loads before recording.

Models are kept in the app’s Application Support/Sayso/Models directory, excluded from backups. Installation stages and validates a replacement before moving the current model. Cancellation and failed validation preserve the previous install. Remove model deletes the installed weights without touching history. Download size is storage/network size, not a peak memory measurement.

## Behavior

- Recognition runs on the device. The normal load path constructs Core ML models from local files directly and never calls FluidAudio’s download/recovery loader. Only the explicit download control accesses the model host.
- Parakeet automatically detects its 25 supported European languages. English and Dutch are supported; Arabic, Chinese, Japanese and Korean are not. Sayso’s language preference applies to Apple Speech. Vocabulary hints currently apply to Apple Speech and writing styles, not Parakeet.
- This first version uses batch transcription after Stop. There is no live Parakeet transcript. Audio is converted to mono Float32 at 16 kHz in memory; microphone audio is never written to disk. Recordings stop at ten minutes.
- Stop, Discard, interruptions and keyboard dictation use the same controller flows. There is no partial Parakeet text to recover before inference finishes. Real background finalization and locked-device behavior need acceptance on the intended iPhone.
- On an iPhone, Core ML is configured for CPU and Neural Engine. Simulator inference uses CPU only. A new runtime/decoder state is created for each operation, and the router releases it after completion/cancellation. Core ML work already in flight may finish unwinding after cancellation; its stale result cannot replace a newer recording.

## Dependencies and attribution

The Xcode project pins [FluidAudio 0.15.6](https://github.com/FluidInference/FluidAudio/tree/v0.15.6), revision `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b`, in Package.resolved. This package includes its NemoTextProcessing binary dependency. The implementation uses this exact release’s API; older manual-loading examples use different model filenames.

Parakeet was created by NVIDIA; the Core ML export is provided by Fluid Inference. Model attribution and the model card are linked in Settings. Consult the [model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) for the model’s terms and [FluidAudio’s license](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/LICENSE) for the runtime.

## Verification

Focused automated coverage checks provider routing, missing models without fallback, cancellation and stale results, safe model replacement, audio conversion and tails, duration bounds. UI coverage checks that Apple Speech is the default and that Parakeet can be selected and set up explicitly.

The following historical checks predate the removal of audio import on 10 September 2026. Import-specific checks and the production file converter are no longer part of the app.

Verified on 8 September 2026 with Xcode 27 beta 6 (`27A5252f`):

- **35 focused tests passed:** 14 local capture/conversion tests and 21 provider/model-install tests. These include both stereo channel layouts, right-channel-only integer WAV import, explicit four-channel mixing, ten-minute conversion boundaries, cancellation races, Apple as the default and installing an independent local model copy.
- **145 distinct methods have passing latest results** across the broader run and focused rerun: 143 unit methods and two UI methods. The existing opt-in physical-iPhone Apple Speech probe was skipped. The broad run retained two test-fixture failures (a missing four-channel layout and an overly short import wait); the focused rerun passed after correcting them. An earlier real right-channel conversion failure was fixed by explicit channel mixing and is retained in the first run’s log.
- **Unsigned device Release build passed.** The initial device build ran out of disk space; rebuilding with available space and a fresh build directory succeeded. The final build includes the stereo and Home layout fixes.
- **Real offline Parakeet inference passed** on an Apple M3 Pro running macOS 26.6.2, with networking explicitly denied using `sandbox-exec`. Both the original synthetic AIFF and an Int16 WAV with silent left-channel audio produced the expected normalized words through the production file converter and production runtime. The runtime source hash was `f03e3be2739d55dfc1b1366f69e0c45f500d6803f7b08183103afe1c18cbc60d`; the extracted converter/samples source hash was `abe2859061495eb53ceec891a2f749e75188d37e49afc1c6fe44470a3a7eec3f`.
- **Visual review and UI checks passed:** Apple Speech is initially selected; Parakeet offers download/import controls; Home’s title, waveform and import control remain visible and reachable.

The offline fixture said “Please send the meeting notes tomorrow morning. This recording stays on this computer.” Parakeet returned the same words with a comma between sentences. Initial model preparation on this host took several minutes; subsequent local load and inference succeeded. This is a functional smoke check, not an accuracy or iPhone performance benchmark.

Local evidence (excluded from Git) is in `.build/Parakeet-Final-Tests.xcresult`, `.build/Parakeet-Focused-Final.xcresult`, `.build/parakeet-release-final.log`, and `.build/parakeet-probe/offline-production-converter{,-right-only}.log`. [Machine-readable verification record](verification/parakeet-local.json). Mac or simulator results do not establish iPhone microphone, background, Bluetooth, memory or thermal acceptance.
