// ishi-mcp is an MCP server that exposes git commit history search to AI
// assistants via the Model Context Protocol. It runs over stdio and shells
// out to the ishi Zig binary for query execution.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/louislef299/ishi/mcp/internal/config"
	"github.com/louislef299/ishi/mcp/internal/version"
	"github.com/louislef299/ishi/mcp/pkg/tools"
)

func main() {
	if err := run(); err != nil {
		slog.Error("fatal error", "error", err)
		os.Exit(1)
	}
}

func run() error {
	// Parse config from flags and env vars.
	config.BindFlags()
	cfg, err := config.Parse()
	if err != nil {
		return err
	}

	// Set up structured logging to stderr (stdio JSON-RPC uses stdin/stdout).
	logLevel := slog.LevelInfo
	if os.Getenv("ISHI_MCP_LOG") == "debug" {
		logLevel = slog.LevelDebug
	}
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
		Level: logLevel,
	}))
	slog.SetDefault(logger)

	slog.Info("starting ishi-mcp server", "version", version.String())

	// Create MCP server and register tools.
	s := mcp.NewServer(&mcp.Implementation{
		Name:    "ishi",
		Version: version.String(),
	}, nil)

	tools.Register(s, tools.Options{
		Target:   cfg.Target,
		Username: cfg.Username,
		Password: cfg.Password,
		Database: cfg.Database,
		Model:    cfg.Model,
		Runner:   cfg.Runner,
	})

	// Set up context that cancels on SIGINT/SIGTERM.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	slog.Info("MCP server listening on stdio")

	// Run over stdio until the client disconnects or context is canceled.
	if err := s.Run(ctx, &mcp.StdioTransport{}); err != nil {
		return err
	}

	slog.Info("shutting down")
	return nil
}
