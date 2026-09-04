"""Render dj_break.txt with Orpheus 3B (Canopy Labs, Apache 2.0) via transformers + SNAC.
Avoids the vllm dependency of the orpheus-speech package."""
import os, sys, time
import torch, soundfile as sf
from transformers import AutoModelForCausalLM, AutoTokenizer
from snac import SNAC

text = open(sys.argv[1]).read().strip()
out = sys.argv[2]
voice = sys.argv[3] if len(sys.argv) > 3 else "leo"   # tara, leah, jess, leo, dan, mia, zac, zoe
# canopylabs/orpheus-3b-0.1-ft is gated on HF; Unsloth hosts an ungated copy of the same weights.
model_name = os.environ.get("ORPHEUS_MODEL", "unsloth/orpheus-3b-0.1-ft")

t0 = time.time()
tok = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.bfloat16).cuda()
snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").cuda()
print(f"loaded in {time.time()-t0:.1f}s", flush=True)

t0 = time.time()
ids = tok(f"{voice}: {text}", return_tensors="pt").input_ids
ids = torch.cat([torch.tensor([[128259]]), ids, torch.tensor([[128009, 128260]])], dim=1).cuda()
with torch.no_grad():
    gen = model.generate(ids, max_new_tokens=4000, do_sample=True, temperature=0.6,
                         top_p=0.95, repetition_penalty=1.1, eos_token_id=128258)
seq = gen[0]
starts = (seq == 128257).nonzero(as_tuple=True)[0]
codes = seq[starts[-1] + 1:] if len(starts) else seq
codes = codes[codes != 128258]
codes = codes[: (len(codes) // 7) * 7] - 128266
l1, l2, l3 = [], [], []
for i in range(0, len(codes), 7):
    f = codes[i:i + 7]
    l1.append(f[0]); l2.append(f[1] - 4096)
    l3.append(f[2] - 2 * 4096); l3.append(f[3] - 3 * 4096)
    l2.append(f[4] - 4 * 4096)
    l3.append(f[5] - 5 * 4096); l3.append(f[6] - 6 * 4096)
layers = [torch.tensor(l).unsqueeze(0).cuda() for l in (l1, l2, l3)]
with torch.no_grad():
    audio = snac.decode(layers).squeeze().cpu().numpy()
sf.write(out, audio, 24000)
print(f"rendered {len(audio)/24000:.1f}s of audio in {time.time()-t0:.1f}s -> {out}", flush=True)
