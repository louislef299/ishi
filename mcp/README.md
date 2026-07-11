# ishi-mcp

MCP server that exposes git commit history search to AI assistants via the [Model Context Protocol](https://modelcontextprotocol.io/).

## Architecture

```
editor/agent ──stdio JSON-RPC──▶ ishi-mcp (Go + official MCP SDK)
                                     │ os/exec
                                     ▼
                                ishi query --json (Zig binary)
```

**Why Go?** The official MCP Go SDK gives us protocol/router/stdio for free. The Zig core (embedded inference + hybrid retrieval) stays the moat. The two languages meet at a JSON contract, not FFI.

## Usage

```bash
# Build
cd mcp
go build -o bin/ishi-mcp .

# Run over stdio (blocks until stdin EOF or SIGINT)
./bin/ishi-mcp --target localhost --database postgres

# Or via environment variables
export ISHI_MCP_TARGET=localhost
export ISHI_MCP_DATABASE=postgres
./bin/ishi-mcp

# Enable debug logging
ISHI_MCP_LOG=debug ./bin/ishi-mcp
```

## Configuration

Flags and environment variables:

| Flag | Env Var | Default | Description |
|------|---------|---------|-------------|
| `--target` | `ISHI_MCP_TARGET` | `localhost` | Postgres host for ishi query |
| `--username` | `ISHI_MCP_USERNAME` | `postgres` | Postgres username |
| `--password` | `ISHI_MCP_PASSWORD` | `ishi` | Postgres password |
| `--database` | `ISHI_MCP_DATABASE` | `postgres` | Postgres database name |
| `--model` | `ISHI_MCP_MODEL` | `ai/nomic-embed-text-v1.5` | Embedding model |
| `--runner` | `ISHI_MCP_RUNNER` | `docker` | Model runner (docker or ollama) |

Flags override environment variables.

## Tools

### `ping`

Test connectivity to the ishi MCP server. Returns `"pong"` if operational.

**Arguments:** None

**Example:**
```json
{
  "name": "ping"
}
```

**Response:**
```json
{
  "content": [{"type": "text", "text": "pong"}]
}
```

## Development

### Testing

```bash
go test ./...
go test -race -cover ./...
```

### Code Structure

```
mcp/
├── main.go                  # Stdio entrypoint
├── internal/
│   ├── config/             # Viper/pflag config parsing
│   ├── ishi/               # Exec wrapper for ishi binary
│   └── version/            # Build-time version info
└── pkg/
    └── tools/              # MCP tool registration
```

### Security

This implementation follows [MCP security best practices](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks):

- Clear, honest tool descriptions (no hidden instructions)
- `ReadOnlyHint` and `IdempotentHint` annotations
- No credential leakage in tool descriptions
- Automated tests to prevent tool-poisoning patterns

## Binary Resolution

The `ishi` binary is resolved from:

1. `ISHI_BIN` environment variable (if set)
2. `PATH` lookup (falls back)

This allows testing with mock binaries and custom installation paths.

## Version Information

Build with version metadata:

```bash
go build -ldflags "\
  -X github.com/louislef299/ishi/mcp/internal/version.Version=$(git describe --tags --always --dirty) \
  -X github.com/louislef299/ishi/mcp/internal/version.Commit=$(git rev-parse HEAD) \
  -X github.com/louislef299/ishi/mcp/internal/version.Date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -o bin/ishi-mcp .
```

## What's Next

- **Issue #22**: `query_commits` tool implementation (shells out to `ishi query --json`)
- **Issue #23**: Build integration (compile both `ishi` and `ishi-mcp` in one command)
- **Issue #33**: Zig-side JSON contract (`ishi query --json` output format)
