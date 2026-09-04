# Voice bake-off

Same 1985 Top 40 DJ break (`dj_break.txt`) rendered by three permissively
licensed TTS models on the AI box (GCONZ-WIN-AI, RTX 4090, WSL2 Ubuntu 22.04).
Picked by ear. First results 2026-09-04, all unprocessed, default voices:

| Model | License | Render | Notes |
|---|---|---|---|
| Chatterbox | MIT | 21.8 s audio in 27.6 s | default voice, `exaggeration=0.55`, no reference clip |
| Higgs Audio v2 | Apache 2.0 | 38.5 s audio in 18.2 s | scene-prompted "1985 male radio DJ"; HF repos pinned to July 2025 revisions |
| Orpheus 3B | Apache 2.0 | 27.2 s audio in 66.1 s | voice `leo`; Unsloth's ungated mirror of the Canopy weights |

Higgs Audio **v3** is newer and Boson recommends it, but its license is
research / non-commercial. v2 stays Apache, so v2 is the candidate.

## Running on the AI box

    ./setup.sh      # one-time: uv venvs per model, static ffmpeg, no sudo needed
    ./run_all.sh    # renders out/<model>.wav

Copy this directory to `~/aircheck-bakeoff/scripts/` in WSL first (tar over ssh).

**WSL kills background work when the launching session ends.** `nohup`,
`setsid`, and `disown` do not help; the whole VM is torn down ~8 s after the
last `wsl.exe` exits. A Windows scheduled task does not work either because
the box sits at the login screen (tasks need an interactive logon). What
works from an SSH session is spawning `wsl.exe` through WMI, which puts the
process outside the SSH job object:

    ssh cyberpc 'wmic process call create "wsl.exe -d Ubuntu -- bash /home/gconz/aircheck-bakeoff/scripts/run-detached.sh"'

where `run-detached.sh` is a two-line wrapper that `cd`s and redirects output
to a log. The same trick will be needed for the pack-generation job poller.

## Dependency notes (all fixed in setup.sh / the render scripts)

- Chatterbox's watermarker imports `pkg_resources`; uv venvs omit setuptools
  and setuptools >= 80 removed `pkg_resources`. Pin `setuptools<80`.
- Higgs: Boson rewrote both HF repos in 2026-04/05 for the transformers-native
  integration (config lost `text_config`, tokenizer `model.pth` deleted). The
  GitHub loader needs the old layout, so `render_higgs.py` pins revisions
  `10840182ca4a` (generation) and `9d4988fbd4ad` (tokenizer). Torch pinned to
  2.6 as well.
- Orpheus: official weights are gated on HF; `unsloth/orpheus-3b-0.1-ft` is
  the same model ungated (`ORPHEUS_MODEL` overrides). Torch 2.14 pulled Triton
  into `generate()` and WSL has no C compiler, so torch is 2.6 and
  `run_all.sh` sets `TORCHDYNAMO_DISABLE=1`.
