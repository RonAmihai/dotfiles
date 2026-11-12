package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type reloadRequest struct {
	update    bool
	sessionID string
}

func main() {
	a, err := agentFor(os.Args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if len(os.Args) == 3 && os.Args[1] == "--request" {
		os.Exit(request(a, os.Args[2]))
	}
	os.Exit(launch(a, os.Args[1:]))
}

func request(a agent, kind string) int {
	if kind != "reload" && kind != "update" {
		fmt.Fprintf(os.Stderr, "usage: %s-reload --request reload|update\n", a.name)
		return 2
	}
	requestPath := os.Getenv(a.requestEnv())
	if requestPath == "" {
		fmt.Printf("This session did not start through %s-reload, so it cannot reload.\n", a.name)
		return 1
	}
	sessionID := a.sessionID()
	if sessionID == "" && a.latest == nil {
		fmt.Printf("%s is not set, so the session to resume is unknown.\n", a.sessionEnvs[0])
		return 1
	}
	pendingPath := requestPath + ".tmp"
	if err := os.WriteFile(pendingPath, []byte(kind+" "+sessionID), 0o600); err != nil {
		fmt.Printf("%s-reload: %v\n", a.name, err)
		return 1
	}
	if err := os.Rename(pendingPath, requestPath); err != nil {
		fmt.Printf("%s-reload: %v\n", a.name, err)
		return 1
	}
	session := "the latest session"
	if sessionID != "" {
		session = "session " + sessionID
	}
	if kind == "update" {
		fmt.Printf("Updating %s, then resuming %s.\n", a.title, session)
	} else {
		fmt.Printf("Restarting %s and resuming %s.\n", a.title, session)
	}
	return 0
}

func launch(a agent, launchArgs []string) int {
	requestPath := filepath.Join(os.TempDir(), a.name+"-reload-"+strconv.Itoa(os.Getpid()))
	os.Remove(requestPath)
	defer os.Remove(requestPath)

	// The terminal sends Ctrl+C to the agent as well, so the launcher only has to survive it.
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)

	args := launchArgs
	for {
		child := exec.Command(a.name, args...)
		child.Stdin, child.Stdout, child.Stderr = os.Stdin, os.Stdout, os.Stderr
		child.Env = append(os.Environ(), a.requestEnv()+"="+requestPath)
		if err := child.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "%s-reload: %v\n", a.name, err)
			return 1
		}
		reload, exitCode := supervise(child, requestPath, signals)
		if reload == nil {
			return exitCode
		}
		if reload.update {
			runUpdate(a)
		}
		fmt.Fprintf(os.Stderr, "%s-reload: restarting %s\n", a.name, a.title)
		args = a.relaunch(launchArgs, reload.sessionID)
	}
}

func supervise(child *exec.Cmd, requestPath string, signals <-chan os.Signal) (*reloadRequest, int) {
	exited := make(chan int, 1)
	go func() {
		child.Wait()
		exited <- child.ProcessState.ExitCode()
	}()

	poll := time.NewTicker(250 * time.Millisecond)
	defer poll.Stop()
	for {
		select {
		case exitCode := <-exited:
			return nil, exitCode
		case received := <-signals:
			if received != os.Interrupt {
				child.Process.Signal(received)
			}
		case <-poll.C:
			reload, err := readRequest(requestPath)
			if err != nil {
				continue
			}
			stop(child, exited)
			return reload, 0
		}
	}
}

func readRequest(requestPath string) (*reloadRequest, error) {
	content, err := os.ReadFile(requestPath)
	if err != nil {
		return nil, err
	}
	os.Remove(requestPath)
	kind, sessionID, _ := strings.Cut(string(content), " ")
	return &reloadRequest{update: kind == "update", sessionID: sessionID}, nil
}

func stop(child *exec.Cmd, exited <-chan int) {
	// Windows cannot deliver SIGTERM, so there the launcher goes straight to Kill.
	if child.Process.Signal(syscall.SIGTERM) == nil {
		select {
		case <-exited:
			return
		case <-time.After(10 * time.Second):
		}
	}
	child.Process.Kill()
	<-exited
}

func runUpdate(a agent) {
	command := updateCommand(a.name)
	update := exec.Command(command[0], command[1:]...)
	update.Stdin, update.Stdout, update.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := update.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s-reload: %s failed, resuming on the current version: %v\n", a.name, strings.Join(command, " "), err)
	}
}
