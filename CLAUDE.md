## Pre-commit Requirements

**ALWAYS** run `make docker-build` and ensure it succeeds **before** committing any code to this repository. The Docker image must build cleanly against the full musl-static release pipeline. Do not commit if `make docker-build` fails.

## Act First, Read Less

When making changes, read only what you need to make the edit, then make it.
Do not read more than 3 files before acting. Do not re-read files you already
read. Do not verify things you already know. If you have enough context to make
a change, make it. The user will interrupt you if you are wrong.

