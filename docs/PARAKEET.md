# Using Parakeet

Parakeet is an optional speech model you can use instead of Apple's built-in speech recognition. Once it's downloaded, it works completely offline. In Original mode it doesn't need Apple Intelligence either.

Apple Speech stays the default. Sayso never switches models on its own. If you pick Parakeet and it isn't installed, Sayso tells you instead of falling back.

## Set it up

1. Open **Settings** in Sayso.
2. Under **Speech model**, choose **Parakeet · local**.
3. Tap **Download Parakeet** (about 500 MB). You can also tap **Import model folder…** if you already have the model files.
4. Record as usual. Your text appears after you tap **Finish dictation**.

The first time the model loads can take a few minutes. After that it's quick.

To free up space, tap **Remove model**. This doesn't affect your history.

## Good to know

- **Languages:** Parakeet detects 25 European languages automatically, including English and Dutch. It doesn't support Arabic, Chinese, Japanese or Korean. The language setting in Sayso only affects Apple Speech.
- **No live text:** your words appear after you stop, not while you speak.
- **10-minute limit** per recording.
- **Vocabulary** hints aren't used by Parakeet. They still help with rewriting.
- The model is stored on your iPhone and isn't included in backups.

## Importing the model yourself

If you'd rather not download inside the app, get the files from [Fluid Inference's model page](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). Then choose a folder that contains these items directly:

```text
Preprocessor.mlmodelc/
Encoder.mlmodelc/
Decoder.mlmodelc/
JointDecisionv3.mlmodelc/
parakeet_vocab.json
```

Sayso rejects incomplete or placeholder files. If you clone the model with Git, make sure Git LFS has downloaded the real files. Other model formats (ONNX, NeMo, MLX) aren't supported.

## Credits and licenses

Parakeet was created by NVIDIA. The version Sayso uses was converted for Apple devices by Fluid Inference and runs through [FluidAudio](https://github.com/FluidInference/FluidAudio). See the [model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) for the model's terms, and [FluidAudio's license](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/LICENSE) for the runtime.
