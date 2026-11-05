# GLM-5.3-Flash exlr8 on one Spark

GLM-5.3-Flash on one ASUS GX10 / NVIDIA DGX Spark (GB10, 128 GB), served by [gr8](https://github.com/kindlingai/gr8)
from the K2 width of [kindlingai/glm-5.3-flash-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4):
int4 KV, DFlash2 speculative decoding, four requests at once, and a prompt cache on disk.

> Work in progress: the gr8 changes are in review (kindlingai/gr8#347, #348, #349, #352), and the submodule points at
> their combined branch until they land.

## Run it

```bash
git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
cd glm-5.3-flash-exlr8-1x-spark
docker compose up -d          # the published image, ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark
docker compose logs -f
docker compose exec gr8 gr8 glm53f smoke
```

`docker compose up -d --build` builds the image on the box instead (about 30 minutes cold). CI builds every push and
publishes main as `latest`, each commit as `sha-<commit>`, and each tag under its name (`.github/workflows/image.yml`).

The API is OpenAI's on port 8100. The first boot downloads 87 GB from Hugging Face (the model and the drafter) and
converts the drafter; later boots take about 45 s. Stop any other model on the box first: the weights take 93 GB.

## Knobs

In `.env` next to `compose.yaml` (see `.env.example`):

| knob | default | |
|---|---|---|
| `CAP` | `262208` | KV reservation in tokens: the longest request (prompt + `max_tokens`) plus 64. About 15 KB of memory a token. |
| `DFLASH` | `1` | `1`: a request alone drafts with [DFlash2](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2) (CC BY-NC-ND 4.0), downloaded and converted on the first boot. `0`: MTP only, nothing downloaded. |
| `MENTAT` | `0` | `1`: register with the mentat cluster through the host's mentat daemon, in group `GROUP` (`gr8-glm53f-1x`). |

Any other gr8 option goes in `.env` the same way: [gr8/KNOBS.md](gr8/KNOBS.md) lists them, and
[gr8/docs/FLASH.md](gr8/docs/FLASH.md) covers GLM-5.3-Flash. The image sets `TP=1`, `SESS=4`, `VARIANT=k2`,
`KV_FORMAT=int4`, the prompt cache (`FLASH_CACHE=aligned`, `KV_STORE=@/etc/gr8/kv-store.yaml`), one prefill lane and a
6 GiB boot floor (`Dockerfile`).

## The prompt cache

A prompt's prefill keeps a checkpoint at its last multiple of 4,096 tokens in the `prompts` volume (`kv-store.yaml`,
64 GB at most). A later prompt with the same start, such as an agent's next turn, prefills only the rest, and the output
is the same bit for bit. Checkpoints outlive restarts (a new engine build, release or `CAP` starts empty), and a copy
stays in RAM the box is not using, which the kernel takes back when it needs it.

## Measured

One GX10 on kindling spark-os with the defaults, clocks uncapped, `gr8 glm53f bench`:

| | |
|---|---|
| decode, one request (tok/s) | code 54.7, prose 29.3, structured 66.5 (MTP only: 32.4, 29.2, 32.1) |
| decode, 4 / 8 requests at once | 57 / 59 tok/s in total |
| prefill, 8K / 32K / 128K / 240K | 1,172 / 1,222 / 1,156 / 923 tok/s (1,235 / 1,236 at 8K / 32K with `DFLASH=0`) |
| time to first token, 32K / 240K | 26.7 s / 266 s cold; 0.25 s / 5.7 s from the prompt cache |
| int4 KV against bf16 KV | next-token KL after 8K and 32K prefills: mean 0.013, median 0.0004, top-1 12/12 |
| needle at 128K, count to 200 | pass |
| lowest free memory, 240K prompt | 5.3 GiB |
| boot | 45 s from the cache; first boot 8 min at 160 MB/s |

The GPU reaches 90 C in a 128K prefill and is then held at 1,800 MHz, so the longer prefills are partly capped.
