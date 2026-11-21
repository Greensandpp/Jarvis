# GreenSoil phone-local offline experiment

Continues Greensandpp/Jarvis on an isolated branch. Original 3D home, original
package/settings, LiveKit lab source, PB7/Pine and production remain untouched.
This separate offline test build uses
`com.greensoil.experiment.greensoil_livekit_voice_experiment.offline`; it installs
alongside the existing cloud Voice Lab. Neither existing package is replaced.

## What is implemented

- In-process llama.cpp via pinned llamadart 0.20.4, CPU, 4 threads, 2048 context.
- Exact Qwen3-1.7B Q8_0 model imported with Android document picker; streamed
  copy, byte ceiling, SHA-256 verification, atomic rename and private storage.
- No inference server, HTTP fallback, credentials, model auto-download or INTERNET
  permission, including the generated debug/profile manifests. No runtime API fee
  or session/month quota. 128 output-token bound limits response length, not time.
- Push-to-talk uses ONLY Android's on-device recognizer. Installed language
  support must be verified before capture. No downloads or cloud recognizer.
- One native TTS owner, only engine voices reporting no network requirement and
  no missing install. Never infer female gender from voice ID or altered pitch.
- Stop/background cancels mic, TTS and native inference and invalidates stale
  replies. No automatic resume, recording, persisted chat or background service.
- A new turn interrupts by tapping **Stop reply and listen offline**. Automatic
  acoustic barge-in/wake word is NOT implemented in this first offline lab.

## Setup on iQOO 13

1. Download the encrypted-delivery APK privately; install the separate offline lab.
2. Download the model once via a browser (1,834,426,016 bytes / about 1.71 GiB):
   https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/90862c4b9d2787eaed51d12237eafdfe7c5f6077/Qwen3-1.7B-Q8_0.gguf
3. Open **Import downloaded GGUF model**, choose that file, wait for verification
   and CPU load. Allow at least 4 GB free for download plus private copy.
4. First test typed chat in airplane mode, with Wi-Fi/mobile data off.
5. Optional speech requires Android-installed offline recognition/TTS packs.
   Missing Tamil support is reported and typed chat stays available. App cannot
   install or manufacture an offline Tamil voice. No cloud fallback exists here.
6. Test Listen, mute/Stop, speaking interruption via the button, background and
   phone lock. After reopening press Load saved model if needed.

The 1.7B model is intentionally small. Tamil/Tanglish quality, phone
latency, memory, battery, female voice availability and actual on-device audio
remain unverified until the owner tests. It is not equivalent to Gemini quality.
Cloud voice remains available in the previous separate lab APK/source, optional.
This offline build cannot call cloud services because it has no network permission.

## Verification

CI must pass Flutter analyzer/tests, Kotlin/Android APK compilation, merged APK
permission/identity/ARM64 checks, and real model CPU inference with AF_INET/6
socket creation denied. The latter proves desktop native inference, not phone
microphone/Tamil quality. Only an encrypted APK artifact may leave public CI.
Model weights are never committed. Model: Apache-2.0; runtime: MIT. Review
upstream model/license and runtime notices before any production integration.
