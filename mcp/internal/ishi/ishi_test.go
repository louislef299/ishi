package ishi

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestNew_ResolvesFromPath(t *testing.T) {
	// Use 'echo' as a stand-in since ishi may not be built yet.
	t.Setenv("ISHI_BIN", "")

	// Temporarily add a directory with a mock 'ishi' to PATH.
	mockScript := createMockScript(t, `#!/bin/sh
echo "mock ishi"
`)
	mockDir := filepath.Dir(mockScript)
	mockBin := filepath.Join(mockDir, "ishi")
	if err := os.Rename(mockScript, mockBin); err != nil {
		t.Fatalf("failed to rename mock script: %v", err)
	}

	oldPath := os.Getenv("PATH")
	t.Setenv("PATH", mockDir+":"+oldPath)

	client, err := New()
	if err != nil {
		t.Fatalf("New() failed: %v", err)
	}
	if client.binPath == "" {
		t.Error("expected binPath to be resolved")
	}
	if !strings.Contains(client.binPath, "ishi") {
		t.Errorf("expected binPath to contain 'ishi', got %q", client.binPath)
	}
}

func TestNew_UsesISHI_BIN_Override(t *testing.T) {
	customPath := "/custom/ishi"
	t.Setenv("ISHI_BIN", customPath)

	client, err := New()
	if err != nil {
		t.Fatalf("New() failed: %v", err)
	}
	if client.binPath != customPath {
		t.Errorf("expected binPath=%q, got %q", customPath, client.binPath)
	}
}

func TestRun_Success(t *testing.T) {
	// Create a mock script that echoes JSON.
	mockScript := createMockScript(t, `#!/bin/sh
echo '{"result": "ok"}'
`)

	client := &Client{binPath: mockScript}
	ctx := context.Background()

	stdout, err := client.Run(ctx, "query", "--json", "test")
	if err != nil {
		t.Fatalf("Run() failed: %v", err)
	}

	expected := `{"result": "ok"}`
	if strings.TrimSpace(string(stdout)) != expected {
		t.Errorf("expected stdout=%q, got %q", expected, string(stdout))
	}
}

func TestRun_NonZeroExit(t *testing.T) {
	// Create a mock script that exits with error.
	mockScript := createMockScript(t, `#!/bin/sh
echo "something went wrong" >&2
exit 1
`)

	client := &Client{binPath: mockScript}
	ctx := context.Background()

	_, err := client.Run(ctx, "query", "--json", "test")
	if err == nil {
		t.Fatal("expected error from non-zero exit, got nil")
	}

	// Error should contain stderr message wrapped with context.
	if !strings.Contains(err.Error(), "ishi query failed") {
		t.Errorf("expected error to contain context, got: %v", err)
	}
	if !strings.Contains(err.Error(), "something went wrong") {
		t.Errorf("expected error to contain stderr, got: %v", err)
	}
}

func TestRun_ContextCancellation(t *testing.T) {
	// Create a mock script that sleeps.
	mockScript := createMockScript(t, `#!/bin/sh
sleep 10
`)

	client := &Client{binPath: mockScript}
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately.

	_, err := client.Run(ctx, "query", "--json", "test")
	if err == nil {
		t.Fatal("expected error from canceled context, got nil")
	}
}

// createMockScript writes a shell script to a temp file, makes it executable,
// and returns its path. The test will clean it up automatically.
func createMockScript(t *testing.T, content string) string {
	t.Helper()
	tmpDir := t.TempDir()
	scriptPath := filepath.Join(tmpDir, "mock-ishi")
	if err := os.WriteFile(scriptPath, []byte(content), 0o755); err != nil {
		t.Fatalf("failed to create mock script: %v", err)
	}
	return scriptPath
}

func TestRun_PassesArgumentsCorrectly(t *testing.T) {
	// Create a mock script that echoes all args.
	mockScript := createMockScript(t, `#!/bin/sh
echo "$@"
`)

	client := &Client{binPath: mockScript}
	ctx := context.Background()

	stdout, err := client.Run(ctx, "query", "--json", "my test query")
	if err != nil {
		t.Fatalf("Run() failed: %v", err)
	}

	expected := "query --json my test query"
	if strings.TrimSpace(string(stdout)) != expected {
		t.Errorf("expected stdout=%q, got %q", expected, string(stdout))
	}
}

func TestNew_NotInPath(t *testing.T) {
	// Clear PATH and ISHI_BIN to simulate binary not found.
	t.Setenv("PATH", "")
	t.Setenv("ISHI_BIN", "")

	_, err := New()
	if err == nil {
		t.Fatal("expected error when ishi not in PATH, got nil")
	}
	if !strings.Contains(err.Error(), "ishi binary not found") && !strings.Contains(err.Error(), "executable file not found") {
		t.Errorf("expected 'not found' error, got: %v", err)
	}
}

func init() {
	// Ensure exec.LookPath can find a known binary for TestNew_ResolvesFromPath.
	// We'll use "echo" as a stand-in since ishi may not be built yet.
	if _, err := exec.LookPath("echo"); err != nil {
		panic("test requires 'echo' in PATH")
	}
}
