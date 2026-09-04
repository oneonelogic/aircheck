"""Render dj_break.txt with Chatterbox (Resemble AI, MIT)."""
import sys, time
import torchaudio as ta
from chatterbox.tts import ChatterboxTTS

text = open(sys.argv[1]).read().strip()
out = sys.argv[2]
ref = sys.argv[3] if len(sys.argv) > 3 else None  # optional reference wav for the voice

t0 = time.time()
model = ChatterboxTTS.from_pretrained(device="cuda")
print(f"loaded in {time.time()-t0:.1f}s", flush=True)
t0 = time.time()
kwargs = dict(exaggeration=0.55, cfg_weight=0.4)
if ref:
    kwargs["audio_prompt_path"] = ref
wav = model.generate(text, **kwargs)
ta.save(out, wav, model.sr)
print(f"rendered {wav.shape[-1]/model.sr:.1f}s of audio in {time.time()-t0:.1f}s -> {out}", flush=True)
