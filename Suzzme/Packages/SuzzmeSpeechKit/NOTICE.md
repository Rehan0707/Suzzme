# SuzzmeSpeechKit attribution and modifications

Speech-only subset of FluidInference/FluidAudio v0.15.2, commit
7f963cdc43ba89c5993654f1e138047d517a818d. Apache License 2.0 (LICENSE).
https://github.com/FluidInference/FluidAudio

Suzzme modifications: only PocketTTS and required Swift helpers retained;
ModelNames limited to PocketTTS; all network download/token code removed;
asset resolver is local-only and voice cloning disabled; logger is a no-op;
response-text logging removed. Models are never bundled in this package.

Model assets: PocketTTS by Kyutai, CoreML conversion by Fluid Inference,
https://huggingface.co/FluidInference/pocket-tts-coreml
https://huggingface.co/kyutai/pocket-tts
Licensed CC BY 4.0: https://creativecommons.org/licenses/by/4.0/
Model weights are used unchanged. Suzzme downloads a subset of the compiled
English int8 pack and the predefined Alba voice; no voice cloning is exposed.
