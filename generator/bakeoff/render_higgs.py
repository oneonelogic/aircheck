"""Render dj_break.txt with Higgs Audio v2 (Boson AI, Apache 2.0)."""
import sys, time
import torch, torchaudio
from huggingface_hub import snapshot_download
from boson_multimodal.serve.serve_engine import HiggsAudioServeEngine
from boson_multimodal.data_types import ChatMLSample, Message, AudioContent

text = open(sys.argv[1]).read().strip()
out = sys.argv[2]
# Optional voice reference: a wav and its transcript. Higgs clones the voice
# from the reference when it is given as a prior assistant turn.
ref_wav = sys.argv[3] if len(sys.argv) > 3 else None
ref_txt = open(sys.argv[4]).read().strip() if len(sys.argv) > 4 else None

system_prompt = (
    "Generate audio following instruction.\n\n"
    "<|scene_desc_start|>\n"
    "A male radio DJ speaking energetically into a studio microphone in 1985. "
    "Warm, close-mic'd broadcast voice, upbeat and confident.\n"
    "<|scene_desc_end|>"
)
# Both HF repos were rewritten 2026-04/05 for the transformers-native integration
# (config.json lost text_config, tokenizer model.pth deleted). This repo's own loader
# needs the July 2025 layout, so pin the last revisions before that change.
t0 = time.time()
gen_path = snapshot_download("bosonai/higgs-audio-v2-generation-3B-base", revision="10840182ca4a")
tok_path = snapshot_download("bosonai/higgs-audio-v2-tokenizer", revision="9d4988fbd4ad")
print(f"weights ready in {time.time()-t0:.1f}s", flush=True)
t0 = time.time()
engine = HiggsAudioServeEngine(gen_path, tok_path, device="cuda")
print(f"loaded in {time.time()-t0:.1f}s", flush=True)
t0 = time.time()
messages = [Message(role="system", content=system_prompt)]
if ref_wav:
    messages += [
        Message(role="user", content=ref_txt),
        Message(role="assistant", content=AudioContent(audio_url=ref_wav)),
    ]
messages.append(Message(role="user", content=text))
resp = engine.generate(
    chat_ml_sample=ChatMLSample(messages=messages),
    max_new_tokens=2048, temperature=0.3, top_p=0.95, top_k=50,
    stop_strings=["<|end_of_text|>", "<|eot_id|>"],
)
audio = torch.from_numpy(resp.audio)[None, :]
torchaudio.save(out, audio, resp.sampling_rate)
print(f"rendered {audio.shape[-1]/resp.sampling_rate:.1f}s of audio in {time.time()-t0:.1f}s -> {out}", flush=True)
