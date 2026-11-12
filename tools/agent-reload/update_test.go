package main

import (
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"testing"
)

// installAt creates the file at relPath under root and links bin/name to it
func installAt(t *testing.T, root, name, relPath string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("creating a symlink needs extra rights on Windows")
	}
	target := filepath.Join(root, relPath)
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(root, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(bin, name)); err != nil {
		t.Fatal(err)
	}
	return bin
}

func stubCaskUpdatesItself(t *testing.T, updatesItself bool) {
	t.Helper()
	original := caskUpdatesItself
	caskUpdatesItself = func(string) bool { return updatesItself }
	t.Cleanup(func() { caskUpdatesItself = original })
}

func TestUpdateCommand_HomebrewCask_UpgradesTheCask(t *testing.T) {
	// Arrange
	bin := installAt(t, t.TempDir(), "claude", "Caskroom/claude-code@latest/2.1.310/claude")
	t.Setenv("PATH", bin)
	stubCaskUpdatesItself(t, false)

	// Act
	command := updateCommand("claude")

	// Assert
	want := []string{"brew", "upgrade", "--cask", "claude-code@latest"}
	if !reflect.DeepEqual(command, want) {
		t.Fatalf("got %v, want %v", command, want)
	}
}

func TestUpdateCommand_CaskThatUpdatesItself_RunsAgentUpdate(t *testing.T) {
	// Arrange
	bin := installAt(t, t.TempDir(), "agy", "Caskroom/antigravity-cli/1.4.7/antigravity")
	t.Setenv("PATH", bin)
	stubCaskUpdatesItself(t, true)

	// Act
	command := updateCommand("agy")

	// Assert
	want := []string{"agy", "update"}
	if !reflect.DeepEqual(command, want) {
		t.Fatalf("got %v, want %v", command, want)
	}
}

func TestUpdateCommand_HomebrewFormula_UpgradesTheFormula(t *testing.T) {
	// Arrange
	bin := installAt(t, t.TempDir(), "opencode", "Cellar/opencode/2.1.4/bin/opencode")
	t.Setenv("PATH", bin)

	// Act
	command := updateCommand("opencode")

	// Assert
	want := []string{"brew", "upgrade", "opencode"}
	if !reflect.DeepEqual(command, want) {
		t.Fatalf("got %v, want %v", command, want)
	}
}

func TestUpdateCommand_WrapperFirstOnPath_UpgradesTheHomebrewCask(t *testing.T) {
	// Arrange
	root := t.TempDir()
	bin := installAt(t, root, "claude", "Caskroom/claude-code@latest/2.1.310/claude")
	wrapper := filepath.Join(root, "wrapper")
	if err := os.MkdirAll(wrapper, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wrapper, "claude"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", wrapper+string(os.PathListSeparator)+bin)
	stubCaskUpdatesItself(t, false)

	// Act
	command := updateCommand("claude")

	// Assert
	want := []string{"brew", "upgrade", "--cask", "claude-code@latest"}
	if !reflect.DeepEqual(command, want) {
		t.Fatalf("got %v, want %v", command, want)
	}
}

func TestUpdateCommand_NotHomebrew_RunsAgentUpdate(t *testing.T) {
	// Arrange
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "codex"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)

	// Act
	command := updateCommand("codex")

	// Assert
	want := []string{"codex", "update"}
	if !reflect.DeepEqual(command, want) {
		t.Fatalf("got %v, want %v", command, want)
	}
}
