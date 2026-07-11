// Package tools registers ishi MCP tools that agents can invoke to
// query git commit history.
package tools

import (
	"context"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// Options holds configuration for tool registration, including database
// connection flags that will be passed to the ishi binary.
type Options struct {
	Target   string // --target flag for ishi (postgres host)
	Username string // --username flag for ishi
	Password string // --password flag for ishi
	Database string // --database flag for ishi
	Model    string // --model flag for ishi
	Runner   string // --runner flag for ishi (docker or ollama)
}

// Register adds the ishi tools to the MCP server.
//
// Tools:
//   - ping — proof-of-concept tool that returns "pong"
func Register(s *mcp.Server, opts Options) {
	annotations := &mcp.ToolAnnotations{
		ReadOnlyHint:   true,
		IdempotentHint: true,
	}

	// ping: proof-of-concept tool to verify MCP integration works end-to-end.
	// This tool does not execute the ishi binary; it's a simple echo to prove
	// the SDK stdio loop is wired correctly. The real query_commits tool will
	// be added in issue #22.
	mcp.AddTool(s, &mcp.Tool{
		Name:        "ping",
		Description: "Test connectivity to the ishi MCP server. Returns 'pong' if the server is operational.",
		Annotations: annotations,
	}, func(_ context.Context, _ *mcp.CallToolRequest, _ any) (*mcp.CallToolResult, any, error) {
		return &mcp.CallToolResult{
			Content: []mcp.Content{&mcp.TextContent{Text: "pong"}},
		}, nil, nil
	})
}
