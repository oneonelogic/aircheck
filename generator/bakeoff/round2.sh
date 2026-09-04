#!/usr/bin/env bash
# Round 2 (2026-09-04): Chatterbox eliminated by ear. Higgs with reference voices,
# Orpheus with its other male voices, then a 1980s FM processing chain on each.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
export TORCHDYNAMO_DISABLE=1 TORCH_COMPILE_DISABLE=1
B=~/aircheck-bakeoff; S="$B/scripts"; VP="$B/higgs-audio/examples/voice_prompts"
cd "$B"; mkdir -p out/r2

for v in en_man chadwick; do
  echo "== higgs ref=$v"
  venv-higgs/bin/python "$S/render_higgs.py" "$S/dj_break.txt" "out/r2/higgs_$v.wav" "$VP/$v.wav" "$VP/$v.txt" 2>&1 | grep -E "ready|loaded|rendered|Error"
done
for v in dan zac; do
  echo "== orpheus voice=$v"
  venv-orpheus/bin/python "$S/render_orpheus.py" "$S/dj_break.txt" "out/r2/orpheus_$v.wav" "$v" 2>&1 | grep -E "loaded|rendered|Error"
done

# 1980s FM air chain, roughly: trim silence, band-limit, presence lift, hard
# compression with fast release, brickwall. No music bed yet (no ACE-Step).
# Trim leading silence, then trailing silence via the reverse trick. A positive
# stop_periods on silenceremove truncates at the FIRST mid-clip pause, which is
# what bit the first run of this script.
CHAIN="silenceremove=start_periods=1:start_threshold=-45dB,\
areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,\
highpass=f=90,lowpass=f=12000,\
equalizer=f=180:t=q:w=1.2:g=2,equalizer=f=3200:t=q:w=1:g=3.5,\
acompressor=threshold=-20dB:ratio=5:attack=4:release=90:makeup=7,\
alimiter=limit=0.93:level=false,\
aresample=44100"
for f in out/r2/*.wav out/higgs.wav out/orpheus.wav; do
  n=$(basename "$f" .wav); [[ $n == *_fm ]] && continue
  ffmpeg -loglevel error -y -i "$f" -af "$CHAIN" -ac 1 "out/r2/${n}_fm.wav" && echo "processed $n"
done
echo ROUND2_DONE; ls -la out/r2/
