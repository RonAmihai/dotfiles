package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type agent struct {
	name         string
	title        string
	sessionEnvs  []string
	resume       func(sessionID string) []string
	latest       []string
	sessionFlags map[string]bool
	options      func() map[string]arity
	unknownArity arity
}

var agents = map[string]agent{
	"claude": {
		name:        "claude",
		title:       "Claude Code",
		sessionEnvs: []string{"CLAUDE_CODE_SESSION_ID"},
		resume:      claudeResume,
		sessionFlags: map[string]bool{
			"-r": true, "--resume": true,
			"-c": true, "--continue": true,
			"--session-id":   true,
			"--fork-session": true,
			"--from-pr":      true,
			"--teleport":     true,
		},
		options:      func() map[string]arity { return helpOptions("claude") },
		unknownArity: optionalValue,
	},
	"codex": {
		name:         "codex",
		title:        "Codex",
		sessionEnvs:  []string{"CODEX_THREAD_ID", "CODEX_SESSION_ID"},
		resume:       func(sessionID string) []string { return []string{"resume", sessionID} },
		latest:       []string{"resume", "--last"},
		sessionFlags: map[string]bool{"--last": true, "--all": true},
		options:      func() map[string]arity { return helpOptions("codex") },
		unknownArity: optionalValue,
	},
	"agy": {
		name:        "agy",
		title:       "Antigravity",
		sessionEnvs: []string{"ANTIGRAVITY_CONVERSATION_ID"},
		resume:      func(sessionID string) []string { return []string{"--conversation", sessionID} },
		latest:      []string{"--continue"},
		sessionFlags: map[string]bool{
			"-c": true, "--continue": true, "--conversation": true,
			"-i": true, "--prompt-interactive": true,
			"-p": true, "--print": true, "--prompt": true,
		},
		// agy's help shows no value placeholders, so its flags without a value are listed here
		options: func() map[string]arity {
			return map[string]arity{
				"-c": noValue, "--continue": noValue,
				"-p": noValue, "--print": noValue, "--prompt": noValue,
				"--dangerously-skip-permissions": noValue,
				"--disable-slash-commands":       noValue,
				"--new-project":                  noValue,
				"--remote-control":               noValue,
				"--sandbox":                      noValue,
			}
		},
		unknownArity: requiredValue,
	},
}

func agentFor(program string) (agent, error) {
	name := strings.TrimSuffix(strings.TrimSuffix(filepath.Base(program), ".exe"), "-reload")
	if a, known := agents[name]; known {
		return a, nil
	}
	return agent{}, fmt.Errorf("run this program as claude-reload, codex-reload or agy-reload, not as %s", filepath.Base(program))
}

func (a agent) requestEnv() string {
	return strings.ToUpper(a.name) + "_RELOAD_REQUEST"
}

func (a agent) sessionID() string {
	for _, name := range a.sessionEnvs {
		if value := os.Getenv(name); value != "" {
			return value
		}
	}
	return ""
}

func (a agent) relaunch(launchArgs []string, sessionID string) []string {
	resume := a.latest
	if sessionID != "" {
		resume = a.resume(sessionID)
	}
	return relaunchArgs(resume, launchArgs, a.sessionFlags, a.options(), a.unknownArity)
}

func claudeResume(sessionID string) []string {
	if hasTranscript(sessionID) {
		return []string{"--resume", sessionID}
	}
	return []string{"--session-id", sessionID}
}

func hasTranscript(sessionID string) bool {
	configDir := os.Getenv("CLAUDE_CONFIG_DIR")
	if configDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return false
		}
		configDir = filepath.Join(home, ".claude")
	}
	transcripts, _ := filepath.Glob(filepath.Join(configDir, "projects", "*", sessionID+".jsonl"))
	return len(transcripts) > 0
}

func helpOptions(command string) map[string]arity {
	help, err := exec.Command(command, "--help").Output()
	if err != nil {
		return nil
	}
	return parseOptions(string(help))
}
