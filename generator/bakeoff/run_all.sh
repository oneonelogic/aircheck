#!/usr/bin/env bash
# Render the same DJ break with every candidate. Output: ~/aircheck-bakeoff/out/<model>.wav
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
export TORCHDYNAMO_DISABLE=1 TORCH_COMPILE_DISABLE=1   # WSL has no C compiler for Triton
B=~/aircheck-bakeoff; S="$B/scripts"; cd "$B"
for m in chatterbox higgs orpheus; do
  echo "== $m"; t0=$(date +%s)
  "venv-$m/bin/python" "$S/render_$m.py" "$S/dj_break.txt" "out/$m.wav" 2>&1 | grep -v Warning | tail -5
  echo "   $m: $(( $(date +%s) - t0 ))s total"
done
ls -la out/
