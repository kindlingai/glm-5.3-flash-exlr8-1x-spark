# GLM-5.3-Flash exlr8 on one Spark

GLM-5.3-Flash served by [gr8](https://github.com/kindlingai/gr8) on one ASUS GX10 / NVIDIA DGX Spark (GB10, 128 GB),
from the K2 width of the exlr8 release
([kindlingai/glm-5.3-flash-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4)), with:

- **int4 KV**: the attention latent in 4 bits (288 B a token and layer against bf16's 1,024).
- **A prompt cache on disk**: checkpoints of prefilled prompts in a folder that survives restarts, with a copy in RAM
  the box is not using, which the kernel takes back whenever it needs it (`kv-store.yaml`).
- **DFlash2 speculative decoding**: a request alone on the box drafts with the DFlash2 drafter.
- **Boot from Hugging Face**: the first boot downloads the box's part of the release (85 GB) and the drafter into the
  model cache, and converts the drafter there.

> Work in progress. The gr8 changes this needs are in review (kindlingai/gr8#347, #348, #349, #352); the submodule points
> at their combined branch until they land. int4 KV quality against bf16 KV is still being measured.

## Running it

```bash
git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
cd glm-5.3-flash-exlr8-1x-spark
docker compose up -d --build
docker compose logs -f
```

The API is OpenAI's, on port 8100 (`/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/metrics`). Stop any
other model on the box first: the weights take 93 GB of its memory. The first boot downloads about 87 GB; later boots
take about 45 s.

```bash
docker compose exec gr8 gr8 glm53f smoke      # 14 checks against the API
docker compose exec gr8 gr8 glm53f status
```

## Knobs

Set them in `.env` next to `compose.yaml` (`.env.example` lists them), or with `docker run -e`.

| knob | default | what it does |
|---|---|---|
| `CAP` | `262208` | The KV reservation in tokens: the longest request, prompt plus `max_tokens`, plus a page (64) for the guard rows. Every token of it costs about 15 KB of memory (the int4 KV rows of the 12 attention layers, and prefill scratch). At the default, the box's free memory stays above 5 GiB under a 240K prompt. |
| `DFLASH` | `1` | `1`: a request alone on the box drafts with the DFlash2 drafter ([incoai/GLM-5.3-Flash-DFlash2](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2), CC BY-NC-ND 4.0), which the first boot downloads and converts for this box. `0`: MTP only, and the drafter is never downloaded. |
| `MENTAT` | `0` | `0`: the box serves on its own. `1`: it registers with the mentat cluster through the host's mentat daemon and announces its API there, in group `GROUP` (`gr8-glm53f-1x`), which keeps it out of a multi-box Flash cluster. |

Everything else is a gr8 launcher option, and any of them can go in `.env` the same way: see
[gr8/KNOBS.md](gr8/KNOBS.md) for the list, and [gr8/docs/FLASH.md](gr8/docs/FLASH.md) for GLM-5.3-Flash. The image
sets these for the recipe (`Dockerfile`):

| option | value | why |
|---|---|---|
| `TP` | `1` | one box |
| `VARIANT` | `k2` | the one width whose weights fit one box (93.4 GB on the device) |
| `KV_FORMAT` | `int4` | 4-bit KV latent (`g6m4_flash-int4`, the only engine in the image) |
| `FLASH_CACHE`, `KV_STORE` | `aligned`, `@/etc/gr8/kv-store.yaml` | the prompt cache |
| `EXTRA_ARGS` | `--pf-lanes 1` | one prefill lane: the second lane's scratch does not fit beside the weights |
| `EXTRA_ENV` | `GR8_MEM_MIN=6` | the boot keeps 6 GiB free, not gr8's 8, which sits at the edge with the drafter at the default `CAP` |

## The prompt cache

`kv-store.yaml` keeps Flash session checkpoints in the `prompts` volume (64 GB at most) with `persist`, and a spare RAM
cache in front of it. A prompt's prefill keeps a checkpoint at its last prefill grid point, a multiple of 4,096 tokens.
A later prompt that starts with the same tokens, such as an agent's next turn under the same system prompt and tools,
is prefilled from that point. The output is the same as without the cache, bit for bit.

The folder outlives restarts. A boot with another engine build, model release or `CAP` starts it empty. Prompts
shorter than 4,097 tokens keep no checkpoint.

## Measured

One GX10 on kindling spark-os, the defaults above, clocks uncapped (bench cools the box to 55 C before each stage).
`gr8 glm53f bench` (gr8/bench) for decode and prefill.

| | |
|---|---|
| boot from the local cache | 42 s |
| first boot from Hugging Face | 85.2 GB in 8 min; the drafter's conversion 5 s |
| smoke | 14/14 |
| needle at 128K | found |

Decode, one stream, tok/s:

| workload | DFlash2 (`DFLASH=1`) | MTP (`DFLASH=0`) |
|---|---|---|
| code | 52.3 | 32.4 |
| prose | 28.8 | 29.2 |
| structured | 66.6 | 32.1 |

Prefill of a cold prompt, and the same prompt again from the prompt cache:

| prompt | prefill tok/s | time to first token | again, from the cache |
|---|---|---|---|
| 8K | 1,172-1,235 | 6.7 s | 0.3 s |
| 32K | 1,222-1,236 | 26.7 s | 0.25 s |
| 128K | 1,156 | 113 s | 4.2 s |
| 240K | 923 | 266 s | 5.7 s |

The GPU reaches 90 C in a 128K prefill, and from there the bench holds it at 1,800 MHz, so the 128K and 240K numbers
are partly capped. One request decodes at a time (gr8's `SESS=1`): concurrent requests queue, about 45 tok/s in total.

## What is in it

| file | what |
|---|---|
| `Dockerfile` | gr8 (the `gr8/` submodule) cut down to the one engine this recipe runs, `g6m4_flash-int4` at TP=1, and the knobs' defaults |
| `compose.yaml` | the container and its three volumes: model, prompt cache, home |
| `kv-store.yaml` | the prompt cache: a persistent SSD store with a spare RAM cache in front |
| `knobs.sh`, `entrypoint.sh`, `bin/gr8` | `MENTAT` mapped onto gr8's options for the boot and for every `gr8` command |
