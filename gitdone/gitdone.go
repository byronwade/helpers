package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"bufio"

	"github.com/fatih/color"
)

var (
	info    = color.New(color.FgCyan).PrintfFunc()
	success = color.New(color.FgGreen).PrintfFunc()
	warn    = color.New(color.FgYellow).PrintfFunc()
	errorLog = color.New(color.FgRed).PrintfFunc()
)

// Run a shell command and return the output
func runCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("error running command: %v\nStderr: %s", err, stderr.String())
	}
	return out.String(), nil
}

// Add all changes to staging area
func addAllChanges() error {
	info("Adding all changes to staging area...\n")
	_, err := runCommand("git", "add", ".")
	if err != nil {
		return fmt.Errorf("error adding changes: %v", err)
	}
	success("All changes added to staging area\n")
	return nil
}

// Get git diff
func getGitDiff() (string, error) {
	info("Getting git diff...\n")
	diff, err := runCommand("git", "diff", "--cached")
	if err != nil {
		return "", err
	}
	return diff, nil
}

// Generate commit message using Ollama API
func generateCommitMessage(diff string) (string, error) {
	info("Generating commit message using Ollama API...\n")
	apiUrl := "http://localhost:11434/api/generate"
	model := "llama2"

	requestBody := map[string]string{
		"model":  model,
		"prompt": fmt.Sprintf("Summarize the following git diff in a single, concise sentence suitable for a commit message:\n\n%s", diff),
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("error marshaling request body: %v", err)
	}

	resp, err := http.Post(apiUrl, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("error making request to Ollama API: %v", err)
	}
	defer resp.Body.Close()

	var fullResponse strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()

		var ollamaResp map[string]interface{}
		err := json.Unmarshal([]byte(line), &ollamaResp)
		if err != nil {
			continue
		}

		if response, ok := ollamaResp["response"].(string); ok {
			fullResponse.WriteString(response)
		}

		if done, ok := ollamaResp["done"].(bool); ok && done {
			break
		}
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("error reading response: %v", err)
	}

	commitMsg := strings.TrimSpace(fullResponse.String())
	commitMsg = strings.Trim(commitMsg, "\"")
	
	if len(commitMsg) > 0 {
		commitMsg = strings.ToUpper(commitMsg[:1]) + commitMsg[1:]
		if !strings.HasSuffix(commitMsg, ".") {
			commitMsg += "."
		}
	}
	
	if len(commitMsg) > 72 {
		commitMsg = commitMsg[:69] + "..."
	}
	
	success("Generated commit message: %s\n", commitMsg)
	return commitMsg, nil
}

// Automate git commit and push
func gitCommitAndPush(commitMsg string) error {
	info("Starting git operations...\n")

	status, err := runCommand("git", "status", "--porcelain")
	if err != nil {
		return fmt.Errorf("error checking git status: %v", err)
	}
	if status == "" {
		warn("No changes to commit\n")
		return nil
	}

	_, err = runCommand("git", "commit", "-m", commitMsg)
	if err != nil {
		return fmt.Errorf("error committing changes: %v", err)
	}
	success("Committed changes with message: %s\n", commitMsg)

	branch, err := runCommand("git", "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return fmt.Errorf("error getting current branch: %v", err)
	}
	branch = strings.TrimSpace(branch)

	_, err = runCommand("git", "push", "origin", branch)
	if err != nil {
		return fmt.Errorf("error pushing changes: %v", err)
	}
	success("Pushed changes to origin/%s\n", branch)

	return nil
}

func showLoadingIndicator(done chan bool) {
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	i := 0
	for {
		select {
		case <-done:
			return
		default:
			fmt.Printf("\r%s Working...", frames[i])
			i = (i + 1) % len(frames)
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func main() {
	info("Starting gitdone...\n")

	done := make(chan bool)
	go showLoadingIndicator(done)

	err := addAllChanges()
	if err != nil {
		done <- true
		errorLog("Error adding changes: %v\n", err)
		return
	}

	diff, err := getGitDiff()
	if err != nil {
		done <- true
		errorLog("Error getting git diff: %v\n", err)
		return
	}

	if diff == "" {
		done <- true
		warn("No changes to commit.\n")
		return
	}

	commitMsg, err := generateCommitMessage(diff)
	if err != nil {
		done <- true
		errorLog("Error generating commit message: %v\n", err)
		return
	}

	if commitMsg == "" {
		done <- true
		errorLog("Generated commit message is empty\n")
		return
	}

	err = gitCommitAndPush(commitMsg)
	if err != nil {
		done <- true
		errorLog("Error in git operations: %v\n", err)
		return
	}

	done <- true
	success("\ngitdone completed successfully.\n")
}
