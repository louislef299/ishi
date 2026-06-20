# ishi

Embeds your git commit history into a pgvector database for semantic similarity
search. The more you commit, the smarter it gets.

*ishi* means ["within"][Black Speech of Mordor].

## Prerequisites

- Zig (0.16.0)
- Docker Desktop (with [Model Runner][] enabled)
- (Optional) Ollama — alternative model runner (`--runner ollama`)
- (Optional) `psql`

To install the dependencies with [`brew`][] leveraging the `Brewfile`, run a
quick `brew bundle check --all -v` to verify which dependencies you are missing
and `brew bundle install -v` to install all the dependencies.

## Setup

```sh
docker compose up -d   # starts pgvector + pulls the embedding model
zig build
```

## Usage

```sh
./zig-out/bin/ishi init
./zig-out/bin/ishi seed --path src/seed.json
./zig-out/bin/ishi query "what is comptime?"
./zig-out/bin/ishi --help
```

## Ollama (alternative runner)

ishi defaults to [Docker Model Runner][Model Runner] for embeddings. To use
Ollama instead, pass `--runner ollama` and pull the model yourself:

```sh
ollama pull nomic-embed-text
./zig-out/bin/ishi seed --runner ollama --model nomic-embed-text --git
```
