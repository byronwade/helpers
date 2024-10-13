package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"
)

// Run a shell command and return the output
func runCommand(name string, args ...string) (string, error) {
	fmt.Printf("Running command: %s %v\n", name, args)
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

// Get git diff
func getGitDiff() (string, error) {
	fmt.Println("Getting git diff...")
	return runCommand("git", "diff", "--cached") // This shows staged changes
}

// OllamaRequest represents the structure of the Ollama API request
type OllamaRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
}

// OllamaResponse represents the structure of each line in the Ollama API response
type OllamaResponse struct {
	Model     string `json:"model"`
	CreatedAt string `json:"created_at"`
	Response  string `json:"response"`
	Done      bool   `json:"done"`
}

// Generate commit message using Ollama API
func generateCommitMessage(diff string) (string, error) {
	fmt.Println("Generating commit message using Ollama API...")
	apiUrl := "http://localhost:11434/api/generate"
	model := "llama2"

	requestBody := OllamaRequest{
		Model:  model,
		Prompt: fmt.Sprintf("Generate a concise git commit message based on the following git diff:\n\n%s", diff),
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("error marshaling request body: %v", err)
	}

	fmt.Printf("Sending request to Ollama API: %s\n", string(jsonBody))
	resp, err := http.Post(apiUrl, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("error making request to Ollama API: %v", err)
	}
	defer resp.Body.Close()

	var fullResponse strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		fmt.Printf("Raw response line: %s\n", line)

		var ollamaResp OllamaResponse
		err := json.Unmarshal([]byte(line), &ollamaResp)
		if err != nil {
			fmt.Printf("Error parsing line: %v\n", err)
			continue
		}

		fullResponse.WriteString(ollamaResp.Response)
		if ollamaResp.Done {
			break
		}
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("error reading response: %v", err)
	}

	commitMsg := strings.TrimSpace(fullResponse.String())
	fmt.Printf("Generated commit message: %s\n", commitMsg)
	return commitMsg, nil
}

// Automate git commit and push
func gitCommitAndPush(commitMsg string) error {
	fmt.Println("Starting git operations...")

	// Check if there are changes to commit
	status, err := runCommand("git", "status", "--porcelain")
	if err != nil {
		return fmt.Errorf("error checking git status: %v", err)
	}
	if status == "" {
		fmt.Println("No changes to commit")
		return nil
	}

	// Commit changes with the provided message
	_, err = runCommand("git", "commit", "-m", commitMsg)
	if err != nil {
		return fmt.Errorf("error committing changes: %v", err)
	}
	fmt.Println("Committed changes with message:", commitMsg)

	// Get the current branch name
	branch, err := runCommand("git", "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return fmt.Errorf("error getting current branch: %v", err)
	}
	branch = strings.TrimSpace(branch)

	// Push to origin
	_, err = runCommand("git", "push", "origin", branch)
	if err != nil {
		return fmt.Errorf("error pushing changes: %v", err)
	}
	fmt.Printf("Pushed changes to origin/%s\n", branch)

	return nil
}

func main() {
	fmt.Println("Starting gitdone...")

	// Step 1: Add all changes to staging area
	err := addAllChanges()
	if err != nil {
		log.Fatal("Error adding changes:", err)
	}

	// Step 2: Get the git diff
	diff, err := getGitDiff()
	if err != nil {
		log.Fatal("Error getting git diff:", err)
	}

	if diff == "" {
		fmt.Println("No changes to commit.")
		return
	}

	fmt.Printf("Git diff:\n%s\n", diff)

	// Step 3: Generate a commit message
	commitMsg, err := generateCommitMessage(diff)
	if err != nil {
		log.Fatal("Error generating commit message:", err)
	}

	if commitMsg == "" {
		log.Fatal("Generated commit message is empty")
	}

	// Step 4: Commit and push the changes
	err = gitCommitAndPush(commitMsg)
	if err != nil {
		log.Fatal("Error in git operations:", err)
	}

	fmt.Println("gitdone completed successfully.")
}
