# KindlingAI: GLM-5.3-Flash EXLR8 on one DGX Spark

If you are an agent booting this for someone, read [AGENTS.md](AGENTS.md) first, then the Quickstart.

_**Join our discord to learn more about KindlingAI and `gr8`: https://discord.gg/8EAvYPV2rE**_

GLM-5.3-Flash on one DGX Spark (GB10, 128 GB), served by [gr8](https://github.com/kindlingai/gr8)
from the bit201 manifest of [kindlingai/glm-5.3-flash-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-flash-exlr8-k2-k3-k4):
K2, with the 124 routed experts that carry the most routing weight at tool-call positions at K3.

![GLM-5.3-Flash on one GB10: decode, prefill and concurrency](docs/card.png)

![Four requests decoding at once on one GB10, at 2x speed](docs/concurrency-4.gif)

## What you need

- One DGX Spark, or another GB10 box such as the ASUS GX10 (128 GB).
- Docker and the NVIDIA container toolkit (both come with DGX OS).
- At least 87 GB of free disk for the download (the model and the drafter), and up to 64 GB more for the prompt cache.
- No other model running on the box: the weights take 93 GB.

## Quickstart

On the Spark, run the published image:

```bash
docker run -d --name glm53f-1x-spark --gpus all --network host --pid host \
  --ulimit memlock=-1 --ulimit core=0 --cap-drop ALL --cap-add IPC_LOCK \
  --security-opt no-new-privileges --read-only --tmpfs /tmp:size=1g,mode=1777 --init --oom-score-adj 1000 \
  -v glm53f-cache:/var/lib/gr8/cache -v glm53f-prompts:/var/lib/gr8/prompts -v glm53f-home:/var/lib/gr8/home \
  ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest
docker logs -f glm53f-1x-spark     # ready at "serving: http://..."
```

The first boot downloads 87 GB from Hugging Face into the `glm53f-cache` volume and converts the drafter: about
10 minutes in all. Later boots take about 45 s.

The API is OpenAI's on port 8100, and the model's name is `glm-5.3-flash` (`glm53f` also works):

```bash
curl -s localhost:8100/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "glm-5.3-flash",
  "messages": [{"role": "user", "content": "Write a haiku about a small computer."}],
  "max_tokens": 4096
}'
```

The model thinks before it answers. The thinking comes back in `message.reasoning` and counts toward `max_tokens`, so
a small `max_tokens` can end before `message.content` starts.

```bash
docker exec glm53f-1x-spark gr8 glm53f smoke   # 14 checks against the API
docker stop glm53f-1x-spark && docker rm glm53f-1x-spark
```

Set a knob (below) with `-e`, for example `-e CAP=262208`. `:latest` is main. Each commit is also published as
`sha-<commit>`, and each tag under its name.

## Run it with compose

`compose.yaml` runs the same image with the same settings, and reads the knobs from `.env`:

```bash
git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
cd glm-5.3-flash-exlr8-1x-spark
docker compose up -d
docker compose logs -f
docker compose exec gr8 gr8 glm53f smoke
```

`docker compose up -d --build` builds the image on the box instead (about 30 minutes cold).

## Knobs

Set these in `.env` next to `compose.yaml` (see `.env.example`), or with `docker run -e`:

| knob | default | |
|---|---|---|
| `TUNE` | `speed` | What to prioritize, see below. Any other value stops the boot. |
| `CAP` | `700032` | The KV pool in tokens, shared by the sessions. Each request reserves its prompt + `max_tokens` from it. |
| `MAX_MODEL_LEN` | `262144` (`700018` with `TUNE=context`) | The longest single request, prompt and output together. At most `CAP` less 14. |
| `DFLASH` | `1` | `1` drafts with [DFlash2](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2) (CC BY-NC-ND 4.0), downloaded on the first boot. `0` uses MTP only and downloads nothing. |
| `MENTAT` | `0` | `1` registers with the mentat cluster through the host's mentat daemon, in group `GROUP` (`gr8-glm53f-1x`). |
| `DEFAULT_PRESENCE_PENALTY` | `greedy=0.2,greedy.thinking=0.5` | A presence penalty for greedy requests (temperature 0) only, to stop exact repeats. `0` turns it off. |

`CAP` was tuned on a standard DGX OS install. On Kindling Spark OS (https://github.com/kindlingai/kindling-spark-os)
you may be able to raise `CAP` to `1000000`.

The image pins the weights to fixed Hugging Face commits. Set `MODEL` or `DRAFTER` in `.env` to change them
(`https://huggingface.co/<org>/<repo>@<commit>`).

[gr8/KNOBS.md](https://github.com/kindlingai/gr8/blob/e7d5c1f/KNOBS.md) lists the advanced `gr8` options, which you
can also set in `.env`.

## Pick what to prioritize

`TUNE` picks one of three settings:

- `speed` (the default): a request can be up to 262,144 tokens.
- `context`: one request up to 700,018 tokens. With a `CAP` below 700,032, also set `MAX_MODEL_LEN` to at most `CAP`
  less 14, or the boot stops.
- `quality`: the same as `speed`. K3 and K4 do not fit one box.

If you set `MAX_MODEL_LEN` yourself, `TUNE` leaves it alone.

## Run another model

A box runs one model at a time. To switch, stop and remove this one first:

```bash
docker stop glm53f-1x-spark && docker rm glm53f-1x-spark   # compose: docker compose down
```

The model stays in the `glm53f-cache` volume, so a later start downloads nothing. To free the disk (87 GB, and up to
64 GB of prompt checkpoints), remove the volumes:

```bash
docker volume rm glm53f-cache glm53f-prompts glm53f-home   # compose: docker compose down -v
```

[gr8's Recipes](https://github.com/kindlingai/gr8#recipes) lists the other models and the number of boxes each one
needs.

## Help

Ask on Discord (https://discord.gg/8EAvYPV2rE) or open an issue in this repo
(https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark/issues). Include the command you ran and the end of
`docker logs glm53f-1x-spark`. Remove addresses and hostnames before you post.
