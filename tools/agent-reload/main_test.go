package main

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
)

func TestHasTranscript_FileInAProjectFolder_ReturnsTrue(t *testing.T) {
	// Arrange
	configDir := t.TempDir()
	t.Setenv("CLAUDE_CONFIG_DIR", configDir)
	projectDir := filepath.Join(configDir, "projects", "-Users-me-repo")
	if err := os.MkdirAll(projectDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projectDir, "saved-id.jsonl"), nil, 0o600); err != nil {
		t.Fatal(err)
	}

	// Act
	saved := hasTranscript("saved-id")

	// Assert
	if !saved {
		t.Error("hasTranscript() = false, want true")
	}
}

func TestHasTranscript_NoFile_ReturnsFalse(t *testing.T) {
	// Arrange
	t.Setenv("CLAUDE_CONFIG_DIR", t.TempDir())

	// Act
	saved := hasTranscript("unsaved-id")

	// Assert
	if saved {
		t.Error("hasTranscript() = true, want false")
	}
}

func TestClaudeResume_UnsavedSession_StartsItWithSameID(t *testing.T) {
	// Arrange
	t.Setenv("CLAUDE_CONFIG_DIR", t.TempDir())

	// Act
	got := claudeResume("S")

	// Assert
	want := []string{"--session-id", "S"}
	if !slices.Equal(got, want) {
		t.Errorf("claudeResume() = %q, want %q", got, want)
	}
}

func TestAgentFor(t *testing.T) {
	tests := []struct {
		program string
		want    string
	}{
		{"claude-reload", "claude"},
		{"/home/me/.local/bin/codex-reload", "codex"},
		{"agy-reload.exe", "agy"},
	}
	for _, tt := range tests {
		t.Run("AgentFor_"+tt.want, func(t *testing.T) {
			// Act
			got, err := agentFor(filepath.FromSlash(tt.program))

			// Assert
			if err != nil || got.name != tt.want {
				t.Errorf("agentFor(%q) = %q, %v, want %q", tt.program, got.name, err, tt.want)
			}
		})
	}
}

func TestAgentFor_UnknownName_ReturnsError(t *testing.T) {
	// Act
	_, err := agentFor("agent-reload")

	// Assert
	if err == nil {
		t.Error("agentFor(agent-reload) returned no error")
	}
}

func TestRequest_AgyWithoutConversationID_AsksForTheLatest(t *testing.T) {
	// Arrange
	requestPath := filepath.Join(t.TempDir(), "request")
	t.Setenv("AGY_RELOAD_REQUEST", requestPath)
	t.Setenv("ANTIGRAVITY_CONVERSATION_ID", "")

	// Act
	code := request(agents["agy"], "reload")

	// Assert
	content, err := os.ReadFile(requestPath)
	if code != 0 || err != nil || string(content) != "reload " {
		t.Errorf("request() = %d, file %q, %v, want 0 and %q", code, content, err, "reload ")
	}
}

func TestRequest_ClaudeWithoutSessionID_Fails(t *testing.T) {
	// Arrange
	requestPath := filepath.Join(t.TempDir(), "request")
	t.Setenv("CLAUDE_RELOAD_REQUEST", requestPath)
	t.Setenv("CLAUDE_CODE_SESSION_ID", "")

	// Act
	code := request(agents["claude"], "reload")

	// Assert
	if _, err := os.Stat(requestPath); code != 1 || err == nil {
		t.Errorf("request() = %d with a request file, want 1 and no file", code)
	}
}

func TestLaunch_CodexAsksForReload_ResumesThreadWithSameFlags(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the fake codex is a shell script")
	}
	// Arrange
	dir := t.TempDir()
	argsFile := filepath.Join(dir, "args")
	fake := `#!/bin/sh
[ "$1" = --help ] && exit 0
if [ ! -e "$FAKE_STARTED" ]; then
    : > "$FAKE_STARTED"
    printf 'reload T1' > "$CODEX_RELOAD_REQUEST"
    exec sleep 30
fi
printf '%s\n' "$@" > "$FAKE_ARGS"
`
	if err := os.WriteFile(filepath.Join(dir, "codex"), []byte(fake), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("FAKE_STARTED", filepath.Join(dir, "started"))
	t.Setenv("FAKE_ARGS", argsFile)

	// Act
	code := launch(agents["codex"], []string{"-m", "o3", "fix it"})

	// Assert
	content, err := os.ReadFile(argsFile)
	got := strings.Fields(string(content))
	want := []string{"resume", "T1", "-m", "o3"}
	if code != 0 || err != nil || !slices.Equal(got, want) {
		t.Errorf("launch() = %d, relaunch args %q, %v, want 0 and %q", code, got, err, want)
	}
}
