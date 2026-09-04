"""Render dj_break.txt with Higgs Audio v2 (Boson AI, Apache 2.0)."""
import sys, time
import torch, torchaudio
from boson_multimodal.serve.serve_engine import HiggsAudioServeEngine
from boson_multimodal.data_types import ChatMLSample, Message

text = open(sys.argv[1]).read().strip()
out = sys.argv[2]

system_prompt = (
    "Generate audio following instruction.\n\n"
    "<|scene_desc_start|>\n"
    "A male radio DJ speaking energetically into a studio microphone in 1985. "
    "Warm, close-mic'd broadcast voice, upbeat and confident.\n"
    "<|scene_desc_end|>"
)
t0 = time.time()
engine = HiggsAudioServeEngine(
    "bosonai/higgs-audio-v2-generation-3B-base",
    "bosonai/higgs-audio-v2-tokenizer",
    device="cuda",
)
print(f"loaded in {time.time()-t0:.1f}s", flush=True)
t0 = time.time()
resp = engine.generate(
    chat_ml_sample=ChatMLSample(messages=[
        Message(role="system", content=system_prompt),
        Message(role="user", content=text),
    ]),
    max_new_tokens=2048, temperature=0.3, top_p=0.95, top_k=50,
    stop_strings=["<|end_of_text|>", "<|eot_id|>"],
)
audio = torch.from_numpy(resp.audio)[None, :]
torchaudio.save(out, audio, resp.sampling_rate)
print(f"rendered {audio.shape[-1]/resp.sampling_rate:.1f}s of audio in {time.time()-t0:.1f}s -> {out}", flush=True)
