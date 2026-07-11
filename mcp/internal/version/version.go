// Package version provides build-time version information derived from git.
package version

// These variables are set at build time via -ldflags.
// Example: go build -ldflags "-X github.com/louislef299/ishi/mcp/internal/version.Version=$(git describe --tags --always --dirty)"
var (
	// Version is the semantic version string (e.g., "v0.1.0", "v0.1.0-3-gabcdef").
	Version = "dev"
	
	// Commit is the git commit SHA.
	Commit = "unknown"
	
	// Date is the build date.
	Date = "unknown"
)

// String returns the version string.
func String() string {
	return Version
}

// Full returns a detailed version string including commit and date.
func Full() string {
	return Version + " (" + Commit + ", built " + Date + ")"
}
