# ishi

Embeds your git commit history into a pgvector database for semantic similarity
search. The more you commit, the smarter it gets.

*ishi* means ["within"][Black Speech of Mordor].

## Prerequisites

- Zig (0.15.2)
- Docker / Docker Compose
- Ollama with an embedding model pulled (`nomic-embed-text`,
  `mxbai-embed-large`, etc.)

## Setup

```sh
docker compose up -d
ollama pull nomic-embed-text
zig build
```

## Usage

```sh
./zig-out/bin/ishi init
./zig-out/bin/ishi seed --path src/seed.json
./zig-out/bin/ishi --help
```

[Black Speech of Mordor]: https://tolkiengateway.net/wiki/Black_Speech
