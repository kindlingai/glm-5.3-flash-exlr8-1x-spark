# For agents: boot GLM-5.3-Flash on one DGX Spark

You are booting this recipe for someone. This file has the steps, every knob, and how to check each step. It is taken
from README.md, `knobs.sh`, `.env.example`, `compose.yaml`, the `Dockerfile` and gr8 (the `gr8/` submodule). If this
file and `knobs.sh` or `compose.yaml` disagree, follow `knobs.sh` and `compose.yaml`, and tell the person. If you
cannot run a check yourself, ask the person to run it and paste the output. Do not skip it.

## 1. Check the box

- It is a DGX Spark, or another GB10 box such as the ASUS GX10 (128 GB).
- Docker and the NVIDIA container toolkit are installed (both come with DGX OS): `docker info | grep -i nvidia` shows
  the `nvidia` runtime.
- Free disk where Docker keeps volumes: at least 87 GB for the download (the model and the drafter), plus up to 64 GB
  for the prompt cache. Check with `df -h "$(docker info --format '{{.DockerRootDir}}')"`. With compose, you can set
  `MODEL_CACHE_DIR` and `PROMPT_CACHE_DIR` to host directories owned by uid 1000 instead.
- The box can reach Hugging Face for the download: `curl -sI https://huggingface.co` answers.
- No other model runs on the box: `docker ps` shows no other model container, and `nvidia-smi` shows no GPU process.
  The weights take 93 GB, and gr8 does not start while another gr8 engine runs on the box.
- Optional: gr8 logs a warning at boot when proactive memory compaction is on. `sysctl vm.compaction_proactiveness`
  prints 0 when it is off. To turn it off, as root, once (gr8/docs/DEPLOY.md):

  ```bash
  echo 'vm.compaction_proactiveness = 0' > /etc/sysctl.d/90-gr8-no-proactive-compaction.conf
  sysctl -w vm.compaction_proactiveness=0
  ```

## 2. Pick the settings

Set the values in `.env` (compose) or with `docker run -e`.

`TUNE` picks what to prioritize. Ask the person whether they need one request longer than 262,144 tokens: then use
`context`. Otherwise, or if you cannot ask, use the default.

| `TUNE` | the settings it sets (`knobs.sh`) | what it gives |
|---|---|---|
| `speed` (default) | `MAX_MODEL_LEN=262144` | the settings README.md's numbers were measured with: requests up to 262,144 tokens |
| `context` | `MAX_MODEL_LEN=700018` | one request up to 700,018 tokens: the 700,032-token pool less DFlash2's 14 guard rows. A request that long leaves little room in the pool, and other requests wait |
| `quality` | `MAX_MODEL_LEN=262144` | the same as `speed`: K2 is the one width of the release that fits one box, and the image builds only the int4 KV engine |

What else `knobs.sh` does:

- If you set `MAX_MODEL_LEN` yourself, `TUNE` leaves it alone.
- With `TUNE=context` and a `CAP` below 700,032, set `MAX_MODEL_LEN` too, to at most `CAP` less 14. When
  `MAX_MODEL_LEN` is more than `CAP`, the boot stops.
- Any other `TUNE` value stops the boot.

Every knob:

| knob | values | default |
|---|---|---|
| `TUNE` | `speed`, `context`, `quality` | `speed` |
| `CAP` | the KV pool in tokens, shared by the sessions, a multiple of 64; about 5 KB of memory a token. It was tuned on DGX OS. README.md says Kindling Spark OS may allow `1000000`; that is not measured (section 6) | `700032` |
| `MAX_MODEL_LEN` | the longest single request, prompt and output together: at most `CAP` less the guard rows (14 with DFlash2), and at most 1,048,576 | by `TUNE` (table above) |
| `DFLASH` | `1`: a request alone drafts with the DFlash2 drafter (licence CC BY-NC-ND 4.0), downloaded and converted on the first boot. `0`: MTP only, nothing downloaded | `1` |
| `MENTAT` | `0`: this box alone. `1`: register with the `mentat` cluster through the host's `mentat` daemon, in group `GROUP` | `0` |
| `GROUP` | the `mentat` group to register in, with `MENTAT=1` | `gr8-glm53f-1x` |
| `DEFAULT_PRESENCE_PENALTY` | for greedy requests (temperature 0) only; `0` turns it off. The format is in gr8/KNOBS.md | `greedy=0.2,greedy.thinking=0.5` |
| `MODEL_CACHE_DIR`, `PROMPT_CACHE_DIR`, `GR8_HOME_DIR` | compose only: host directories in place of compose's volumes, owned by uid 1000 | compose's volumes |
| `IMAGE` | compose only: a pinned image, e.g. `ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:sha-<commit>` | `:latest` |
| `MODEL` | the release, `https://huggingface.co/<org>/<repo>@<commit>` | the commit README.md's numbers were measured with |
| `DRAFTER` | the drafter, `https://huggingface.co/<org>/<repo>@<commit>` | the commit README.md's numbers were measured with |
| `HF_TOKEN` | sent only to Hugging Face, for a gated or private repo | none |

Any other gr8 launcher option works too (gr8/KNOBS.md).

## 3. Boot

The commands below use `TUNE=speed`: put in the value you picked.

1. Optional: print the settings the boot will use. Compare the `MAX_MODEL_LEN=` and `CAP=` lines under
   "cluster options" with the `TUNE` table above.

   ```bash
   docker run --rm -e TUNE=speed ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest show-config --no-check
   ```

2. Optional: `check` runs the boot's own checks on the box without booting: the model's files in the cache, no other
   engine running, free memory. It prints a `FAIL` line for each problem, ends with `check: N failed`, and exits 1 if
   N is not 0. Before the first boot it lists the model as not in the cache yet and the drafter as not converted yet:
   the first boot downloads and converts them. Any other `FAIL` line is a problem to fix before step 3. Tell the
   person what it says before you change anything on the box.

   ```bash
   docker run --rm --gpus all --network host --pid host -e TUNE=speed \
     -v glm53f-cache:/var/lib/gr8/cache -v glm53f-prompts:/var/lib/gr8/prompts -v glm53f-home:/var/lib/gr8/home \
     ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest check
   ```

3. Start the container:

   ```bash
   docker run -d --name glm53f-1x-spark --gpus all --network host --pid host \
     --ulimit memlock=-1 --ulimit core=0 --cap-drop ALL --cap-add IPC_LOCK \
     --security-opt no-new-privileges --read-only --tmpfs /tmp:size=1g,mode=1777 --init --oom-score-adj 1000 \
     -e TUNE=speed \
     -v glm53f-cache:/var/lib/gr8/cache -v glm53f-prompts:/var/lib/gr8/prompts -v glm53f-home:/var/lib/gr8/home \
     ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest
   ```

   The first boot downloads 87 GB from Hugging Face into the `glm53f-cache` volume (the model and the drafter) and
   converts the drafter: README.md gives about 10 minutes in all, and about 50 s for later boots. With `mentat`, add
   `-e MENTAT=1`.

   Or with compose:

   ```bash
   git clone --recurse-submodules https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark
   cd glm-5.3-flash-exlr8-1x-spark
   cp .env.example .env          # optional: uncomment TUNE, or any other knob, and set it
   docker compose up -d
   ```

   Compose keeps the model in its own volumes, not in the `glm53f-*` volumes of `docker run`, so the first compose
   boot downloads the model even after a `docker run` boot.

4. To change `TUNE` or any other knob later: stop and remove the container, then start it again with the new value,
   the same way as before (compose: `docker compose down`, edit `.env`, `docker compose up -d`). A change of `TUNE` or
   `MAX_MODEL_LEN` alone downloads nothing: the model and the drafter stay in the cache volume. A new `MODEL` or
   `DRAFTER` commit, or `DFLASH=1` after boots with `DFLASH=0`, downloads what the cache does not have yet.

## 4. Check that it serves

Wait for `serving:` in the log first; the checks after it confirm it.

- `docker logs -f glm53f-1x-spark` (compose: `docker compose logs -f`) prints `serving: http://...` when the box
  serves.
- `docker exec glm53f-1x-spark gr8 glm53f health` exits 0 when the box serves. With compose, `docker compose ps`
  shows the container as `healthy` once this check passes.
- The API's `/health` answers 200 once the box serves. Before that it answers another code, or does not answer:
  `curl -s -o /dev/null -w '%{http_code}\n' localhost:8100/health`.
- `docker exec glm53f-1x-spark gr8 glm53f status` shows the box's state, engine and free memory.
- `docker exec glm53f-1x-spark gr8 glm53f smoke` runs gr8's smoke test, 14 checks against the API. It ends with
  `14/14 passed` and exits 0 when every check passes.
- The API is OpenAI-compatible, on port 8100, with the model name `glm-5.3-flash` (`glm53f` also works). Send one
  chat:

  ```bash
  curl -s localhost:8100/v1/chat/completions -H 'Content-Type: application/json' -d '{
    "model": "glm-5.3-flash",
    "messages": [{"role": "user", "content": "Write a haiku about a small computer."}],
    "max_tokens": 4096
  }'
  ```

  The reply is JSON with a `choices` list. The model thinks before it answers: the thinking comes back in
  `message.reasoning` and counts toward `max_tokens`. This request took about 1,700 tokens. With a small `max_tokens`,
  the reply can stop during the thinking, with `message.content` empty.
- To stop: `docker stop glm53f-1x-spark && docker rm glm53f-1x-spark` (compose: `docker compose down`).

## 5. When a step fails

| what you see | what to do |
|---|---|
| `TUNE=...: want speed (the default), context or quality ...` | use one of the three values |
| `gr8: --max-model-len ...: more than CAP ..., the KV pool a request comes from` | set `MAX_MODEL_LEN` to at most `CAP` less 14, or raise `CAP` |
| `MENTAT=...: want 0 (this box alone) or 1 (register with the mentat cluster)` | use `MENTAT=0` or `MENTAT=1` |
| `gr8: memlock is limited ...` | `--ulimit memlock=-1` with `docker run`, `ulimits.memlock: -1` in compose |
| `gr8: ... is not writable by uid 1000 ...` | run `chown 1000:1000` on the host directory you set as `GR8_HOME_DIR` |
| `an engine is already running` or `a g6m4 --rank process is running` | ask the person, then stop the other model (README.md, Run another model) |
| the image does not pull | build the image on the box, in a clone with its submodule. `docker compose build` (about 30 minutes cold) tags it `ghcr.io/kindlingai/glm-5.3-flash-exlr8-1x-spark:latest`. Without compose, `docker buildx build --platform linux/arm64 -t glm53f-1x-spark .`, then use the tag `glm53f-1x-spark` |

The container exits with 0 after a stop, 1 when the engine failed, and 2 for bad options.
`docker inspect -f '{{.State.ExitCode}}' glm53f-1x-spark` prints it.

Read the log:

- After the container exits: `docker logs glm53f-1x-spark` (compose: `docker compose logs`). It has the launcher's
  output, and it is there until you remove the container.
- While the container runs: `docker exec glm53f-1x-spark gr8 glm53f logs supervisor` (or `shim` or `front`; with no
  name after `logs`, the engine's log).

If a step fails for a reason not listed here, ask on the KindlingAI Discord (the link is at the top of README.md).

## 6. Not measured yet: tell the person

This list is the recipe's checklist of what is still to be measured. If the person measures one of these, ask them to
post the numbers on Discord or in an issue (https://github.com/kindlingai/glm-5.3-flash-exlr8-1x-spark/issues).

- `TUNE=context` was measured once, on the box of README.md's benchmark card, with `MAX_MODEL_LEN` raised: one
  672K-token prompt (README.md, More numbers). The lowest free memory was 3.9 GiB on Kindling Spark OS; README.md
  gives about 2 GiB less on DGX OS.
- The K2 width that every `TUNE` value runs has not been scored against BF16: the release card scores K4 only, and
  says to measure K2 on your own workload before relying on it.
- A `CAP` above 700,032: README.md says Kindling Spark OS may allow `1000000`. This recipe has no measurement there.
