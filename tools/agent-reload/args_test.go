package main

import (
	"maps"
	"slices"
	"testing"
)

func TestParseOptions(t *testing.T) {
	// Arrange
	help := `Options:
  --add-dir <directories...>            Additional directories to allow tool
  --allowedTools, --allowed-tools <tools...>
  --bg, --background                    Start the session in the background and
                                        --resume <session-id>, continues that
  -c, --continue                        Continue the most recent conversation in
  --ide                                 Automatically connect to IDE on startup
  --model <model>                       Model for the current session. Provide
  -r, --resume [value]                  Resume a conversation by session ID or
`
	want := map[string]arity{
		"--add-dir":       manyValues,
		"--allowedTools":  manyValues,
		"--allowed-tools": manyValues,
		"--bg":            noValue,
		"--background":    noValue,
		"-c":              noValue,
		"--continue":      noValue,
		"--ide":           noValue,
		"--model":         requiredValue,
		"-r":              optionalValue,
		"--resume":        optionalValue,
	}

	// Act
	got := parseOptions(help)

	// Assert
	if !maps.Equal(got, want) {
		t.Errorf("parseOptions() = %v, want %v", got, want)
	}
}

func TestParseOptions_ClapHelp_ReadsIndentedFlagsAndRepeatedValues(t *testing.T) {
	// Arrange
	help := `Options:
  -c, --config <key=value>
          Override a configuration value

      --last
          Continue the most recent session without showing the picker

  -i, --image <FILE>...
          Optional image(s) to attach to the initial prompt
`
	want := map[string]arity{
		"-c":       requiredValue,
		"--config": requiredValue,
		"--last":   noValue,
		"-i":       manyValues,
		"--image":  manyValues,
	}

	// Act
	got := parseOptions(help)

	// Assert
	if !maps.Equal(got, want) {
		t.Errorf("parseOptions() = %v, want %v", got, want)
	}
}

func TestRelaunchArgs_Claude(t *testing.T) {
	// Arrange
	options := map[string]arity{
		"--add-dir":    manyValues,
		"-c":           noValue,
		"--continue":   noValue,
		"--ide":        noValue,
		"--model":      requiredValue,
		"-r":           optionalValue,
		"--resume":     optionalValue,
		"--session-id": requiredValue,
	}
	resume := []string{"--resume", "S"}
	tests := []struct {
		name       string
		launchArgs []string
		want       []string
	}{
		{"RelaunchArgs_NoArgs_ResumesSession", nil, []string{"--resume", "S"}},
		{"RelaunchArgs_FlagsWithValues_KeepsThem", []string{"--ide", "--model", "haiku"}, []string{"--resume", "S", "--ide", "--model", "haiku"}},
		{"RelaunchArgs_ResumeWithoutValue_ReplacesIt", []string{"--ide", "--resume"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_ResumeWithValue_DropsOldSession", []string{"-r", "OLD", "--ide"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_InlineSessionID_DropsIt", []string{"--session-id=OLD", "--ide"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_Continue_DropsIt", []string{"-c", "--ide"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_PromptAfterBooleanFlag_DropsPrompt", []string{"--ide", "fix the bug"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_PromptFirst_DropsPrompt", []string{"fix the bug", "--ide"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_PromptAfterDoubleDash_DropsPrompt", []string{"--ide", "--", "-fix"}, []string{"--resume", "S", "--ide"}},
		{"RelaunchArgs_ManyValues_KeepsAllUntilNextFlag", []string{"--add-dir", "a", "b", "--ide"}, []string{"--resume", "S", "--add-dir", "a", "b", "--ide"}},
		{"RelaunchArgs_UnknownFlag_KeepsNextWord", []string{"--new-flag", "x"}, []string{"--resume", "S", "--new-flag", "x"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Act
			got := relaunchArgs(resume, tt.launchArgs, agents["claude"].sessionFlags, options, optionalValue)

			// Assert
			if !slices.Equal(got, tt.want) {
				t.Errorf("relaunchArgs(%q) = %q, want %q", tt.launchArgs, got, tt.want)
			}
		})
	}
}

func TestRelaunchArgs_Codex(t *testing.T) {
	// Arrange
	options := map[string]arity{"-m": requiredValue, "--model": requiredValue, "--last": noValue, "--search": noValue}
	resume := []string{"resume", "T"}
	tests := []struct {
		name       string
		launchArgs []string
		want       []string
	}{
		{"RelaunchArgs_ModelAndPrompt_KeepsModelDropsPrompt", []string{"-m", "o3", "fix it"}, []string{"resume", "T", "-m", "o3"}},
		{"RelaunchArgs_StartedWithResumeLast_DropsOldResume", []string{"resume", "--last", "--search"}, []string{"resume", "T", "--search"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Act
			got := relaunchArgs(resume, tt.launchArgs, agents["codex"].sessionFlags, options, optionalValue)

			// Assert
			if !slices.Equal(got, tt.want) {
				t.Errorf("relaunchArgs(%q) = %q, want %q", tt.launchArgs, got, tt.want)
			}
		})
	}
}

func TestRelaunchArgs_Agy(t *testing.T) {
	// Arrange
	a := agents["agy"]
	resume := []string{"--conversation", "C"}
	tests := []struct {
		name       string
		launchArgs []string
		want       []string
	}{
		{"RelaunchArgs_BooleanFlagThenPrompt_DropsPrompt", []string{"--sandbox", "fix it"}, []string{"--conversation", "C", "--sandbox"}},
		{"RelaunchArgs_ValueFlag_KeepsValue", []string{"--model", "flash", "--effort", "high"}, []string{"--conversation", "C", "--model", "flash", "--effort", "high"}},
		{"RelaunchArgs_InitialPrompt_DropsItWithItsValue", []string{"-i", "start here", "--sandbox"}, []string{"--conversation", "C", "--sandbox"}},
		{"RelaunchArgs_Continue_DropsIt", []string{"-c", "--model", "flash"}, []string{"--conversation", "C", "--model", "flash"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Act
			got := relaunchArgs(resume, tt.launchArgs, a.sessionFlags, a.options(), a.unknownArity)

			// Assert
			if !slices.Equal(got, tt.want) {
				t.Errorf("relaunchArgs(%q) = %q, want %q", tt.launchArgs, got, tt.want)
			}
		})
	}
}
