## Pre-commit Requirements

**ALWAYS** run a clean build **before** committing any code to this repository. Pick the right target for the *current* platform:

- **Linux**: run `make docker-build` — the Docker image must build cleanly against the full musl-static release pipeline.
- **macOS / FreeBSD / other**: run `make binary` — the native local build must succeed. Do **not** run `make docker-build` here; Docker on non-Linux hosts is slow and not the canonical pipeline for those platforms.

Do not commit if the build fails.

## Act First, Read Less

When making changes, read only what you need to make the edit, then make it.
Do not read more than 3 files before acting. Do not re-read files you already
read. Do not verify things you already know. If you have enough context to make
a change, make it. The user will interrupt you if you are wrong.

