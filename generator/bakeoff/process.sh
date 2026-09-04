#!/usr/bin/env bash
# Apply the FM air chain to every raw clip in out/ and out/r2/. Rerunnable alone.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
B=~/aircheck-bakeoff; cd "$B"; mkdir -p out/r2
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
echo PROCESS_DONE
