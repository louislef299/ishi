package config

import (
	"os"
	"testing"

	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

func TestParse_Defaults(t *testing.T) {
	// Reset viper and pflag for isolated test.
	viper.Reset()
	pflag.CommandLine = pflag.NewFlagSet(os.Args[0], pflag.ContinueOnError)

	BindFlags()
	cfg, err := Parse()
	if err != nil {
		t.Fatalf("Parse() failed: %v", err)
	}

	// Verify defaults.
	if cfg.Target != "localhost" {
		t.Errorf("expected target=localhost, got %q", cfg.Target)
	}
	if cfg.Username != "postgres" {
		t.Errorf("expected username=postgres, got %q", cfg.Username)
	}
	if cfg.Password != "ishi" {
		t.Errorf("expected password=ishi, got %q", cfg.Password)
	}
	if cfg.Database != "postgres" {
		t.Errorf("expected database=postgres, got %q", cfg.Database)
	}
	if cfg.Model != "ai/nomic-embed-text-v1.5" {
		t.Errorf("expected model=ai/nomic-embed-text-v1.5, got %q", cfg.Model)
	}
	if cfg.Runner != "docker" {
		t.Errorf("expected runner=docker, got %q", cfg.Runner)
	}
}

func TestParse_EnvVars(t *testing.T) {
	// Reset viper and pflag for isolated test.
	viper.Reset()
	pflag.CommandLine = pflag.NewFlagSet(os.Args[0], pflag.ContinueOnError)

	// Set env vars.
	t.Setenv("ISHI_MCP_TARGET", "custom-host")
	t.Setenv("ISHI_MCP_USERNAME", "custom-user")
	t.Setenv("ISHI_MCP_PASSWORD", "custom-pass")
	t.Setenv("ISHI_MCP_DATABASE", "custom-db")
	t.Setenv("ISHI_MCP_MODEL", "custom-model")
	t.Setenv("ISHI_MCP_RUNNER", "ollama")

	BindFlags()
	cfg, err := Parse()
	if err != nil {
		t.Fatalf("Parse() failed: %v", err)
	}

	// Verify env vars override defaults.
	if cfg.Target != "custom-host" {
		t.Errorf("expected target=custom-host, got %q", cfg.Target)
	}
	if cfg.Username != "custom-user" {
		t.Errorf("expected username=custom-user, got %q", cfg.Username)
	}
	if cfg.Password != "custom-pass" {
		t.Errorf("expected password=custom-pass, got %q", cfg.Password)
	}
	if cfg.Database != "custom-db" {
		t.Errorf("expected database=custom-db, got %q", cfg.Database)
	}
	if cfg.Model != "custom-model" {
		t.Errorf("expected model=custom-model, got %q", cfg.Model)
	}
	if cfg.Runner != "ollama" {
		t.Errorf("expected runner=ollama, got %q", cfg.Runner)
	}
}

func TestParse_FlagsOverrideEnv(t *testing.T) {
	// Reset viper and pflag for isolated test.
	viper.Reset()
	pflag.CommandLine = pflag.NewFlagSet(os.Args[0], pflag.ContinueOnError)

	// Set env var.
	t.Setenv("ISHI_MCP_TARGET", "env-host")

	BindFlags()

	// Set flag (should override env).
	os.Args = []string{"test", "--target=flag-host"}

	cfg, err := Parse()
	if err != nil {
		t.Fatalf("Parse() failed: %v", err)
	}

	// Verify flag overrides env.
	if cfg.Target != "flag-host" {
		t.Errorf("expected target=flag-host, got %q", cfg.Target)
	}
}
