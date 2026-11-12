package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

var caskUpdatesItself = func(token string) bool {
	out, err := exec.Command("brew", "info", "--json=v2", "--cask", token).Output()
	if err != nil {
		return false
	}
	var info struct {
		Casks []struct {
			AutoUpdates bool `json:"auto_updates"`
		} `json:"casks"`
	}
	return json.Unmarshal(out, &info) == nil && len(info.Casks) == 1 && info.Casks[0].AutoUpdates
}

// Claude Code refuses to update a Homebrew install and only prints the brew command
func updateCommand(name string) []string {
	if upgrade := homebrewUpgrade(name); upgrade != nil {
		return upgrade
	}
	return []string{name, "update"}
}

// A wrapper such as cmux's can come first on PATH, so every PATH entry is checked
func homebrewUpgrade(name string) []string {
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		target, err := filepath.EvalSymlinks(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		parts := strings.Split(filepath.ToSlash(target), "/")
		for i := 0; i+1 < len(parts); i++ {
			switch parts[i] {
			case "Caskroom":
				if caskUpdatesItself(parts[i+1]) {
					return nil
				}
				return []string{"brew", "upgrade", "--cask", parts[i+1]}
			case "Cellar":
				return []string{"brew", "upgrade", parts[i+1]}
			}
		}
	}
	return nil
}
