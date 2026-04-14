## Pre-commit Requirements

**ALWAYS** run `make docker-build` and ensure it succeeds **before** committing any code to this repository. The Docker image must build cleanly against the full musl-static release pipeline. Do not commit if `make docker-build` fails.
