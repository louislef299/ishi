// Package ishi provides an exec wrapper for the ishi Zig binary.
// It shells out to `ishi query --json` and returns the JSON output.
package ishi

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Client wraps the ishi binary for execution.
type Client struct {
	binPath string
}

// New creates a new ishi client. It resolves the binary path from the
// ISHI_BIN environment variable, or falls back to searching PATH.
func New() (*Client, error) {
	binPath := os.Getenv("ISHI_BIN")
	if binPath == "" {
		var err error
		binPath, err = exec.LookPath("ishi")
		if err != nil {
			return nil, fmt.Errorf("ishi binary not found in PATH: %w", err)
		}
	}
	return &Client{binPath: binPath}, nil
}

// Run executes the ishi binary with the given arguments and returns stdout.
// If the command exits non-zero, it returns an error wrapping stderr.
func (c *Client) Run(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, c.binPath, args...)
	
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		stderrText := strings.TrimSpace(stderr.String())
		if stderrText == "" {
			stderrText = err.Error()
		}
		return nil, fmt.Errorf("ishi query failed: %s", stderrText)
	}

	return stdout.Bytes(), nil
}
