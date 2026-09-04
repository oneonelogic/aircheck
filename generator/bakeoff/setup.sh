#!/usr/bin/env bash
# One-time setup of the voice bake-off on the AI box (WSL Ubuntu). Idempotent.
# No sudo: ffmpeg is a static binary in ~/.local/bin, libsndfile comes with the soundfile wheel.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
B=~/aircheck-bakeoff; mkdir -p "$B/out"; cd "$B"

if ! command -v ffmpeg >/dev/null; then
  echo "== ffmpeg (static)"
  curl -sL https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz | tar xJ
  cp ffmpeg-*-static/ffmpeg ffmpeg-*-static/ffprobe ~/.local/bin/ && rm -rf ffmpeg-*-static
fi
ffmpeg -version | head -1

echo "== chatterbox"
[ -d venv-chatterbox ] || uv venv venv-chatterbox --python 3.11 -q
uv pip install -q --python venv-chatterbox/bin/python chatterbox-tts soundfile

echo "== higgs-audio"
[ -d higgs-audio ] || git clone -q https://github.com/boson-ai/higgs-audio
[ -d venv-higgs ] || uv venv venv-higgs --python 3.10 -q
uv pip install -q --python venv-higgs/bin/python -r higgs-audio/requirements.txt
uv pip install -q --python venv-higgs/bin/python -e higgs-audio soundfile

echo "== orpheus"
[ -d venv-orpheus ] || uv venv venv-orpheus --python 3.10 -q
uv pip install -q --python venv-orpheus/bin/python torch torchaudio transformers accelerate snac soundfile "huggingface_hub[cli]"

echo "SETUP_DONE"
