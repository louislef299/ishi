// Package config handles CLI flag binding and environment variable mapping
// for ishi-mcp. It parses flags and env vars via Viper/pflag into a Config
// struct that the application consumes.
package config

import (
	"fmt"
	"strings"

	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

// Viper/pflag key constants. Pflags use hyphens; Viper maps them to
// env vars with underscores (e.g., TARGET -> target).
const (
	TARGET   = "target"
	USERNAME = "username"
	PASSWORD = "password"
	DATABASE = "database"
	MODEL    = "model"
	RUNNER   = "runner"
)

// Config holds the parsed configuration for database connection flags
// that will be forwarded to the ishi binary.
type Config struct {
	Target   string
	Username string
	Password string
	Database string
	Model    string
	Runner   string
}

// BindFlags registers pflags on the default pflag.CommandLine. Call this
// before Parse.
func BindFlags() {
	pflag.String(TARGET, "localhost", "Postgres host for ishi query")
	pflag.String(USERNAME, "postgres", "Postgres username for ishi query")
	pflag.String(PASSWORD, "ishi", "Postgres password for ishi query")
	pflag.String(DATABASE, "postgres", "Postgres database name for ishi query")
	pflag.String(MODEL, "ai/nomic-embed-text-v1.5", "Embedding model for ishi query")
	pflag.String(RUNNER, "docker", "Model runner (docker or ollama) for ishi query")
}

// Parse binds pflags to Viper, parses CLI args, reads env vars, and
// returns a Config. Call BindFlags first.
func Parse() (Config, error) {
	if err := viper.BindPFlags(pflag.CommandLine); err != nil {
		return Config{}, fmt.Errorf("failed to bind pflags: %w", err)
	}

	// Map env vars like ISHI_MCP_TARGET to target flag.
	viper.SetEnvPrefix("ISHI_MCP")
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))
	viper.AutomaticEnv()

	pflag.Parse()

	cfg := Config{
		Target:   viper.GetString(TARGET),
		Username: viper.GetString(USERNAME),
		Password: viper.GetString(PASSWORD),
		Database: viper.GetString(DATABASE),
		Model:    viper.GetString(MODEL),
		Runner:   viper.GetString(RUNNER),
	}

	return cfg, nil
}
