package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os/exec"
	"strings"
)

// Run a shell command and return the output
func runCommand(name string, args ...string) string {
    cmd := exec.Command(name, args...)
    var out bytes.Buffer
    cmd.Stdout = &out
    if err := cmd.Run(); err != nil {
        log.Fatal(err)
    }
    return out.String()
}

// Get git diff
func getGitDiff() string {
    return runCommand("git", "diff", "--cached") // This shows staged changes
}

// Generate commit message using Ollama API
func generateCommitMessage(diff string) (string, error) {
    apiUrl := "http://localhost:11434/api/generate" // Replace this with the actual Ollama API endpoint
    model := "llama2" // Replace with the correct model ID
    
    requestBody := fmt.Sprintf(`{
        "model": "%s",
        "prompt": "Generate a concise git commit message based on the following git diff: %s"
    }`, model, diff)

    resp, err := http.Post(apiUrl, "application/json", bytes.NewBuffer([]byte(requestBody)))
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()

    body, err := ioutil.ReadAll(resp.Body)
    if err != nil {
        return "", err
    }

    return strings.TrimSpace(string(body)), nil
}

// Automate git add, commit, push
func gitCommitAndPush(commitMsg string) {
    // Add all changes
    runCommand("git", "add", ".")

    // Commit changes with AI-generated message
    runCommand("git", "commit", "-m", commitMsg)

    // Push to origin main
    runCommand("git", "push", "origin", "main")

    fmt.Println("Pushed changes with commit message:", commitMsg)
}

func main() {
    // Step 1: Get the git diff
    diff := getGitDiff()

    if diff == "" {
        fmt.Println("No changes to commit.")
        return
    }

    // Step 2: Generate a commit message
    commitMsg, err := generateCommitMessage(diff)
    if err != nil {
        log.Fatal("Error generating commit message:", err)
    }

    // Step 3: Commit and push the changes
    gitCommitAndPush(commitMsg)
}
