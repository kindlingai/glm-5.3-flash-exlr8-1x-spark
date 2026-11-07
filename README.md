# KindlingAI: GLM-5.3-Flash EXLR8 on one DGX Spark
**If you are an agent booting this for someone: read [AGENTS.md](AGENTS.md) first, then the Quickstart.**

_**Join our discord to learn more about KindlingAI and `gr8`: https://discord.gg/8EAvYPV2rE**_

GLM-5.3-Flash on one DGX Spark (GB10, 128 GB), served by [gr8](https://github.com/kindlingai/gr8)
from the K2 width of [kindlingai/glm-5.3-flash-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4):
int4 KV, DFlash2 speculative decoding, four requests at once, and a prompt cache on disk.

![GLM-5.3-Flash on one GB10: decode, prefill and concurrency](docs/card.png)

![Four requests decoding at once on one GB10, at 2x speed](docs/concurrency-4.gif)

*Four requests decoding at once on one GB10, played at 2x speed.*

Pick what to prioritize with one setting, `TUNE`:

- `TUNE=speed` (the default): one request writes code at 54.2 tok/s, and a request can be up to 262,144 tokens.
- `TUNE=context`: one request up to 700,018 tokens. A 672K-token prompt took 901 s to the first token, then decoded
  at 16 tok/s.
- `TUNE=quality`: the same as `speed`. K2 is the one width of the release that fits one box.

Details: [Pick what to prioritize](#pick-what-to-prioritize), below the Quickstart.

## What you need

- One DGX Spark, or another GB10 box such as the ASUS GX10 (128 GB).
- Docker and the NVIDIA container toolkit (both come with DGX OS).
- At least 87 GB of free disk for the download (the model and the drafter), and up to 64 GB more for the prompt cache.
- No other model running on the box: the weights take 93 GB.

## Quickstart

On the Spark, with Docker and the NVIDIA container toolkit (both come with DGX OS), run the published image:

```bash
docker run -d --name glm53f-1x-spark --gpus all --network host --pid host \
  --ulimit memlock=-1 --ulimit core=0 --cap-drop ALL --cap-add IPC_LOCK \
  --security-opt no-new-privileges --read-only --tmpfs /tmp:size=1g,mode=1777 --init --oom-score-adj 1000 \
  -v glm53f-cache:/var/lib/gr8/cache -v glm53f-prompts:/var/lib/gr8/prompts -v glm53f-home:/var/lib/gr8/home \
  ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest
docker logs -f glm53f-1x-spark     # ready at "serving: http://..."
```

The first boot downloads 87 GB from Hugging Face into the `glm53f-cache` volume (the model and the drafter) and converts
the drafter: about 10 minutes in all. Later boots take about 50 s. Stop any other model on the box first: the weights
take 93 GB.

The API is OpenAI's on port 8100, and the model's name is `glm-5.3-flash` (`glm53f` also works):

```bash
curl -s localhost:8100/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "glm-5.3-flash",
  "messages": [{"role": "user", "content": "Write a haiku about a small computer."}],
  "max_tokens": 4096
}'
```

The model thinks before it answers. The thinking comes back in `message.reasoning` and counts toward `max_tokens`:
this haiku took about 1,700 tokens, so a small `max_tokens` can end before `message.content` starts.

```bash
docker exec glm53f-1x-spark gr8 glm53f smoke   # 14 checks against the API
docker stop glm53f-1x-spark && docker rm glm53f-1x-spark
```

Set a knob (below) with `-e`, for example `-e CAP=262208`. `:latest` is main. Each commit is also published as
`sha-<commit>`, and each tag under its name.

## Help

Ask on Discord (https://discord.gg/8EAvYPV2rE) or open an issue in this repo
(https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark/issues). Say which step failed, and include:

- the command you ran, and the end of `docker logs glm53f-1x-spark`, before you remove the container;
- if it still runs, `docker exec glm53f-1x-spark gr8 glm53f status`.

Remove addresses and hostnames before you post.

## Run it with compose

`compose.yaml` runs the same image with the same settings, and reads the knobs from `.env`:

```bash
git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
cd glm-5.3-flash-exlr8-1x-spark
docker compose up -d
docker compose logs -f
docker compose exec gr8 gr8 glm53f smoke
```

`docker compose up -d --build` builds the image on the box instead (about 30 minutes cold). CI builds every push
(`.github/workflows/image.yml`).

## Knobs

In `.env` next to `compose.yaml` (see `.env.example`), or with `docker run -e`:

| knob | default | |
|---|---|---|
| `TUNE` | `speed` | What to prioritize: `speed`, `context` or `quality` (see [Pick what to prioritize](#pick-what-to-prioritize)). Any other value stops the boot. |
| `CAP` | `700032` | The KV pool in tokens, shared by the sessions: admission reserves each request's prompt + `max_tokens` from it. About 5 KB of memory a token. |
| `MAX_MODEL_LEN` | `262144` (`700018` with `TUNE=context`) | The longest single request, prompt and output together. At most `CAP` less the guard rows (14 with DFlash2). |
| `DFLASH` | `1` | `1`: a request alone drafts with [DFlash2](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2) (CC BY-NC-ND 4.0), downloaded and converted on the first boot. A request left alone when the others finish switches to it after 256 tokens of MTP. `0`: MTP only, nothing downloaded. |
| `MENTAT` | `0` | `1`: register with the mentat cluster through the host's mentat daemon, in group `GROUP` (`gr8-glm53f-1x`). |
| `DEFAULT_PRESENCE_PENALTY` | `greedy=0.2,greedy.thinking=0.5` | For greedy requests (temperature 0) only: a presence penalty of 0.2 on the reply and 0.7 inside the think block. Greedy decoding on this K2 quant can fall into exact repeats, such as the same tool call turn after turn. Sampling requests get none. A request's own `presence_penalty` is added on top. `0` turns it off. The format is in gr8's KNOBS.md. |

`CAP` was tuned on a standard DGX OS install. If you are running Kindling Spark OS (https://github.com/kindlingai/kindling-spark-os)
you may be able to raise `CAP` to `1000000`.

The image pins the weights to the Hugging Face commits measured below: the release at
[`867580a`](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4/tree/867580abd28d142bb4c56218bb81a752b7dea988)
and the drafter at [`bf582e4`](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2/tree/bf582e4eacc1810f76656d1811693ff6c6737d2a).
Set `MODEL` or `DRAFTER` in `.env` as needed (`https://huggingface.co/<org>/<repo>@<commit>`).

Advanced `gr8` options can be specified in `.env` as well: [gr8/KNOBS.md](https://github.com/kindlingai/gr8/blob/e7d5c1f/KNOBS.md) lists them, and
[gr8/docs/FLASH.md](https://github.com/kindlingai/gr8/blob/e7d5c1f/docs/FLASH.md) covers GLM-5.3-Flash. The image sets `TP=1`, `SESS=4`, `VARIANT=k2`,
`KV_FORMAT=int4`, the prompt cache (`FLASH_CACHE=aligned`, `KV_STORE=@/etc/gr8/kv-store.yaml`), one prefill lane and a
5 GiB boot floor (`Dockerfile`).

## Pick what to prioritize

`TUNE` picks one of three sets of settings (`knobs.sh`). On one box it sets only `MAX_MODEL_LEN`, the longest single
request. If you set `MAX_MODEL_LEN` yourself, `TUNE` leaves it alone. With `TUNE=context` and a `CAP` below 700,032,
set `MAX_MODEL_LEN` too, to at most `CAP` less 14: the boot stops when `MAX_MODEL_LEN` is more than `CAP`.

| `TUNE` | sets | you get | you give up | measured |
|---|---|---|---|---|
| `speed` (default) | `MAX_MODEL_LEN=262144` | Decode, one stream: code / prose / structured 54.2 / 28.6 / 66.4 tok/s. Prefill 8K / 32K / 128K: 1,045 / 1,060 / 875 tok/s. 1 / 2 / 4 / 8 streams: 39.8 / 45.2 / 52.7 / 58.1 tok/s in total. | Requests up to 262,144 tokens, prompt and output together. | The benchmark card above: one `gr8 glm53f bench` run of the image's defaults (`kindling.json`). |
| `context` | `MAX_MODEL_LEN=700018`: the 700,032-token pool less DFlash2's 14 guard rows | One request up to 700,018 tokens. A 672K-token prompt: 901 s to the first token, 16 tok/s decode after it, 2.7 s from the prompt cache. | Admission reserves a request's prompt + `max_tokens` from the 700,032-token pool, so other requests wait for room. Any request past 32K tokens decodes alone anyway (gr8's `SHARE_LIMIT`). Under the 672K prompt the lowest free memory was 3.9 GiB on Kindling Spark OS, about 2 GiB less on DGX OS. | The 672K row of More numbers, below: the same box as the benchmark card. |
| `quality` | the same as `speed` | The same as `speed`. | Nothing. | Nothing else to measure: K2 is the one width of the release whose weights fit one box ([gr8/docs/FLASH.md](https://github.com/kindlingai/gr8/blob/e7d5c1f/docs/FLASH.md)), and the image builds only the int4 KV engine. The [release card](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4/blob/867580abd28d142bb4c56218bb81a752b7dea988/README.md) scores K4 against BF16, not K2. |

## The prompt cache

A prompt's prefill keeps a checkpoint at its last multiple of 4,096 tokens in the `prompts` volume (`kv-store.yaml`,
64 GB at most). A later prompt with the same start, such as an agent's next turn, prefills only the rest, and the output
is the same bit for bit. Checkpoints outlive restarts (a new engine build, release or `CAP` starts empty), and a copy
stays in RAM the box is not using, which the kernel takes back when it needs it.

## More numbers

The card above is one `gr8 glm53f bench` run of the image's defaults (`kindling.json`; regenerate it with
`python3 gr8/bench/bench.py kindling REPORT.json --out kindling.json --config-id tp1`, from kindlingai/gr8#354). The rest, from the same box
(one GX10 on Kindling Spark OS, clocks uncapped, the bench cooling to 55 C before each stage):

| | |
|---|---|
| weights on the device | 93.4 GB (K2) |
| KV pool | 700,032 tokens (int4 latent and pooled indexer keys, 3.5 GB), shared by up to 4 sessions. A request past 32K decodes alone (gr8's `SHARE_LIMIT`) |
| longest request | 262,144 tokens, prompt and output together (`MAX_MODEL_LEN`) |
| from the prompt cache | 32K prompt 0.25 s and 240K prompt 5.7 s to the first token |
| int4 KV against bf16 KV | next-token KL after 8K and 32K prefills: mean 0.013, median 0.0004, top-1 12/12 |
| lowest free memory | 3.9 GiB on Kindling Spark OS under a 672K prompt at `CAP` 700,032 (about 2 GiB less on DGX OS) |
| a 672K prompt (with `MAX_MODEL_LEN` raised) | 901 s to the first token, 16 tok/s decode after it, 2.7 s from the prompt cache |
| boot | 45 s from the cache. The first boot downloads the 85 GB model at about 160 MB/s (8 min), then the 2.3 GB drafter, and converts the drafter in 5 s |

The GPU reaches 90 C in a 128K prefill, and the bench then holds it at 1,800 MHz, so the long prefills are partly capped.

To run the bench in the image: `docker exec glm53f-1x-spark gr8 glm53f bench --hosts ''`. Without `--hosts ''` it
stops with `FileNotFoundError: 'ssh'`. The bench reaches the box over ssh to cool and sample its GPU, and the image
has no ssh. With `--hosts ''` the bench does not cool the GPU between stages, unlike the card's run.

## Run another model

A box runs one model at a time, and gr8 does not start while another gr8 engine runs on it. To switch, stop and remove
this one first:

```bash
docker stop glm53f-1x-spark && docker rm glm53f-1x-spark   # compose: docker compose down
```

The model stays in the `glm53f-cache` volume, so a later start of this recipe downloads nothing. To free the disk
(87 GB, and up to 64 GB of prompt checkpoints), remove the volumes:

```bash
docker volume rm glm53f-cache glm53f-prompts glm53f-home   # compose: docker compose down -v
```

[gr8's Recipes](https://github.com/kindlingai/gr8#recipes) lists the other models and the number of boxes each one
needs.
