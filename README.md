# blur-app

Local Linux desktop media toolbox. Overview: `AGENTS.md`. Map: `context/ROUTING.md`.

## Setup
1. Flutter SDK, stable.
2. Fedora build deps: `sudo dnf install clang cmake ninja-build gtk3-devel opencv-devel`
3. Optional, AI: local OpenAI-compatible model server (e.g. Ollama); pick model in app Settings.
4. Optional, GPU for neural blur removal: NVIDIA driver, CUDA 13 runtime, cuDNN 9 (`libcudnn9-cuda-13`). Without them it runs on the processor.

First build downloads ONNX Runtime (234 MB) into `~/.cache/blur-app/deps`.

## Run
`flutter run -d linux`

## Validate
See `AGENTS.md`.
