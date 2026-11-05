# GLM-5.3-Flash exlr8 on one Spark

> Draft, not yet tuned. The numbers below are from the first boots on one GB10; prefill tuning, the KV size and
> DFlash2 at TP=1 are still being measured.

GLM-5.3-Flash served by [gr8](https://github.com/kindlingai/gr8) on one ASUS GX10 / NVIDIA DGX Spark (GB10, 128 GB),
from the K2 width of the exlr8 release
([kindlingai/glm-5.3-flash-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4)), with:

- **int4 KV**: the attention latent in 4 bits (288 B a token and layer against bf16's 1,024).
- **A prompt cache on disk**: checkpoints of prefilled prompts in a folder that survives restarts, with a copy in RAM
  the box is not using, which the kernel takes back whenever it needs it (`kv-store.yaml`).
- **Boot from Hugging Face**: the first boot downloads the box's part of the release (85 GB) into the model cache.

## Running it

```bash
git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
cd glm-5.3-flash-exlr8-1x-spark
docker compose up -d --build
docker compose logs -f
```

The API is OpenAI's, on port 8100. Stop any other model on the box first: the weights take 93 GB of its memory.

```bash
docker compose exec gr8 /opt/gr8/gr8 glm53f smoke
```

## What is in it

| file | what |
|---|---|
| `Dockerfile` | gr8 (the `gr8/` submodule) cut down to the one engine this recipe runs, `g6m4_flash-int4` at TP=1 |
| `compose.yaml` | the container, its three volumes (model, prompt cache, home) and the launcher's options |
| `kv-store.yaml` | the prompt cache: a persistent SSD store with a spare RAM cache in front |

## Measured so far (one GX10 on kindling spark-os, K2, int4 KV, CAP 262,208, one prefill lane)

| | |
|---|---|
| boot, local cache | 42 s (93.4 GB of weights on the device) |
| first boot from Hugging Face | 85.2 GB in 8 min |
| decode, one stream (MTP 1) | code 32.4, prose 29.2, structured 32.1 tok/s |
| smoke test | 14/14 |
