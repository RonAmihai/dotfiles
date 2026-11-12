package main

import (
	"regexp"
	"strings"
)

type arity int

const (
	noValue arity = iota
	optionalValue
	requiredValue
	manyValues
)

var optionLine = regexp.MustCompile(`^ {2,}(?:(-\w), )?(--[\w-]+)(?:, (--[\w-]+))?(?: ([<\[])([^>\]]*)([>\]](?:\.\.\.)?)?)?`)

func parseOptions(help string) map[string]arity {
	options := map[string]arity{}
	for _, line := range strings.Split(help, "\n") {
		match := optionLine.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		value := noValue
		switch {
		case strings.HasSuffix(match[5], "...") || strings.HasSuffix(match[6], "..."):
			value = manyValues
		case match[4] == "<":
			value = requiredValue
		case match[4] == "[":
			value = optionalValue
		}
		for _, name := range match[1:4] {
			if name != "" {
				options[name] = value
			}
		}
	}
	return options
}

// relaunchArgs puts the resume arguments first, then the launch flags with their values, without prompts and old session flags.
func relaunchArgs(resume, launchArgs []string, sessionFlags map[string]bool, options map[string]arity, unknown arity) []string {
	args := append([]string{}, resume...)
	for i := 0; i < len(launchArgs); i++ {
		arg := launchArgs[i]
		if arg == "--" {
			break
		}
		isPrompt := !strings.HasPrefix(arg, "-")
		if isPrompt {
			continue
		}
		name, _, hasInlineValue := strings.Cut(arg, "=")
		end := i + 1
		if !hasInlineValue {
			value, known := options[name]
			if !known {
				value = unknown
			}
			end += valueCount(launchArgs[end:], value)
		}
		if !sessionFlags[name] {
			args = append(args, launchArgs[i:end]...)
		}
		i = end - 1
	}
	return args
}

func valueCount(rest []string, value arity) int {
	switch value {
	case requiredValue:
		return min(1, len(rest))
	case optionalValue:
		if len(rest) > 0 && !strings.HasPrefix(rest[0], "-") {
			return 1
		}
	case manyValues:
		count := 0
		for count < len(rest) && !strings.HasPrefix(rest[count], "-") {
			count++
		}
		return count
	}
	return 0
}
