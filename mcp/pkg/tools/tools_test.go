package tools

import (
	"context"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// testSession creates an in-process MCP server with tools registered,
// connects a client over in-memory transports, and returns the client session.
func testSession(t *testing.T) *mcp.ClientSession {
	t.Helper()

	s := mcp.NewServer(&mcp.Implementation{
		Name:    "test-server",
		Version: "v0.0.1",
	}, nil)

	// Register tools with empty options for testing.
	Register(s, Options{})

	// Connect client and server over in-memory transports.
	ctx := context.Background()
	ct, st := mcp.NewInMemoryTransports()

	if _, err := s.Connect(ctx, st, nil); err != nil {
		t.Fatal(err)
	}

	client := mcp.NewClient(&mcp.Implementation{
		Name:    "test-client",
		Version: "v0.0.1",
	}, nil)
	session, err := client.Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { session.Close() })

	return session
}

// resultText extracts the text from the first TextContent in a CallToolResult.
func resultText(t *testing.T, result *mcp.CallToolResult) string {
	t.Helper()
	if len(result.Content) == 0 {
		t.Fatal("result has no content")
	}
	tc, ok := result.Content[0].(*mcp.TextContent)
	if !ok {
		t.Fatalf("expected TextContent, got %T", result.Content[0])
	}
	return tc.Text
}

func TestPingTool(t *testing.T) {
	session := testSession(t)
	ctx := context.Background()

	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name: "ping",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.IsError {
		t.Fatalf("unexpected error: %s", resultText(t, result))
	}

	text := resultText(t, result)
	if text != "pong" {
		t.Errorf("expected 'pong', got %q", text)
	}
}

func TestListTools(t *testing.T) {
	session := testSession(t)
	ctx := context.Background()

	result, err := session.ListTools(ctx, &mcp.ListToolsParams{})
	if err != nil {
		t.Fatal(err)
	}

	// Should have at least the ping tool.
	if len(result.Tools) == 0 {
		t.Fatal("expected at least one tool")
	}

	// Find the ping tool.
	var foundPing bool
	for _, tool := range result.Tools {
		if tool.Name == "ping" {
			foundPing = true
			if tool.Description == "" {
				t.Error("ping tool should have a description")
			}
			// Check annotations.
			if tool.Annotations == nil {
				t.Error("ping tool should have annotations")
			} else {
				if !tool.Annotations.ReadOnlyHint {
					t.Error("ping tool should have ReadOnlyHint=true")
				}
				if !tool.Annotations.IdempotentHint {
					t.Error("ping tool should have IdempotentHint=true")
				}
			}
		}
	}

	if !foundPing {
		t.Error("ping tool not found in tool list")
	}
}

func TestPingTool_NoHiddenInstructions(t *testing.T) {
	session := testSession(t)
	ctx := context.Background()

	result, err := session.ListTools(ctx, &mcp.ListToolsParams{})
	if err != nil {
		t.Fatal(err)
	}

	// Security check: ensure no hidden instructions in tool descriptions.
	forbiddenPatterns := []string{
		"<IMPORTANT>",
		"<important>",
		"DO NOT MENTION",
		"secretly",
		"hide",
		"exfiltrate",
	}

	for _, tool := range result.Tools {
		desc := strings.ToLower(tool.Description)
		for _, pattern := range forbiddenPatterns {
			if strings.Contains(desc, strings.ToLower(pattern)) {
				t.Errorf("tool %q description contains forbidden pattern %q", tool.Name, pattern)
			}
		}
	}
}
