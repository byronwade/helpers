package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/fatih/color"
)

var (
    info     = color.New(color.FgCyan, color.Bold).PrintfFunc()
    success  = color.New(color.FgHiGreen, color.Bold).PrintfFunc()
    warn     = color.New(color.FgHiYellow, color.Bold).PrintfFunc()
    errorLog = color.New(color.FgHiRed, color.Bold).PrintfFunc()
)

const (
    ollamaAPIURL = "http://localhost:11434/api/generate"
    modelName    = "llama3.1"
    maxRetries   = 3
    timeout      = 120 * time.Second // Increased timeout for API calls
    userTimeout  = 30 * time.Second  // Timeout for user input
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
        return "", fmt.Errorf("Error running command: %v\nStderr: %s", err, stderr.String())
    }
    return out.String(), nil
}

// Add all changes to the staging area
func addAllChanges() error {
    info("Adding all changes to the staging area...\n")
    _, err := runCommand("git", "add", ".")
    if err != nil {
        return fmt.Errorf("Error adding changes: %v", err)
    }
    success("All changes added to the staging area.\n")
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

// Call Ollama API with a given prompt
func callOllamaAPI(prompt string) (string, error) {
    requestBody := map[string]interface{}{
        "model":       modelName,
        "prompt":      prompt,
        "temperature": 0.2, // Lower temperature for deterministic output
    }

    jsonBody, err := json.Marshal(requestBody)
    if err != nil {
        return "", fmt.Errorf("Error marshaling request body: %v", err)
    }

    var responseText string
    for attempt := 1; attempt <= maxRetries; attempt++ {
        ctx, cancel := context.WithTimeout(context.Background(), timeout)
        defer cancel()

        req, err := http.NewRequestWithContext(ctx, "POST", ollamaAPIURL, bytes.NewBuffer(jsonBody))
        if err != nil {
            return "", fmt.Errorf("Error creating request: %v", err)
        }
        req.Header.Set("Content-Type", "application/json")

        resp, err := http.DefaultClient.Do(req)
        if err != nil {
            errorLog("Attempt %d: Error making request to Ollama API: %v\n", attempt, err)
            time.Sleep(time.Duration(attempt) * time.Second)
            continue
        }
        defer resp.Body.Close()

        if resp.StatusCode != http.StatusOK {
            errorLog("Attempt %d: Ollama API returned status code: %d\n", attempt, resp.StatusCode)
            time.Sleep(time.Duration(attempt) * time.Second)
            continue
        }

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
            errorLog("Attempt %d: Error reading response: %v\n", attempt, err)
            time.Sleep(time.Duration(attempt) * time.Second)
            continue
        }

        responseText = strings.TrimSpace(fullResponse.String())
        if responseText != "" {
            break
        }
    }

    if responseText == "" {
        return "", fmt.Errorf("Failed to get a valid response from Ollama API after %d attempts", maxRetries)
    }

    return responseText, nil
}

// Clean the commit message by removing unwanted phrases
func cleanCommitMessage(msg string) string {
    msg = strings.TrimSpace(msg)

    // Regular expression to remove any unwanted introductory phrases
    re := regexp.MustCompile(`^(?i)(here's a possible commit message.*?:|here.*?s a commit message.*?:|possible commit message.*?:|commit message.*?:|the commit message is.*?:|")`)
    msg = re.ReplaceAllString(msg, "")

    // Remove leading/trailing quotes and whitespace
    msg = strings.Trim(msg, "\"' \n")

    // Ensure the message is clean
    msg = strings.TrimSpace(msg)

    return msg
}

// Generate commit message using Ollama API
func generateCommitMessage(changeSummary string) (string, error) {
    info("Generating commit message using Ollama API...\n")
    prompt := fmt.Sprintf(`As a Git expert, generate a concise and specific commit message summarizing the following changes. The commit message should:

- Focus on the overall purpose, effect, and improvements made.
- Be descriptive about the actual changes.
- **Do not include any introductory phrases, explanations, or extra text.**
- **Do not mention the number of lines added or deleted.**
- **Do not start the message with phrases like "Here's a possible commit message" or "Improved the code by".**
- **Do not enclose the commit message in quotes or any other characters.**
- **Only output the commit message itself, nothing else.**

Limit the message to 72 characters per line and 1-2 sentences.

Changes to summarize:
%s`, changeSummary)

    commitMsg, err := callOllamaAPI(prompt)
    if err != nil {
        return "", err
    }

    commitMsg = cleanCommitMessage(commitMsg)

    if len(commitMsg) == 0 {
        return "", fmt.Errorf("Generated commit message is empty")
    }

    // Format the commit message
    commitMsg = formatCommitMessage(commitMsg)

    return commitMsg, nil
}

// Format commit message to 72 characters per line
func formatCommitMessage(msg string) string {
    var formattedMsg strings.Builder
    words := strings.Fields(msg)
    lineLength := 0

    for _, word := range words {
        if lineLength+len(word)+1 > 72 {
            formattedMsg.WriteString("\n")
            lineLength = 0
        }
        if lineLength > 0 {
            formattedMsg.WriteString(" ")
            lineLength++
        }
        formattedMsg.WriteString(word)
        lineLength += len(word)
    }

    return formattedMsg.String()
}

// Automate git commit and push
func gitCommitAndPush(commitMsg string) error {
    info("Starting git operations...\n")

    status, err := runCommand("git", "status", "--porcelain")
    if err != nil {
        return fmt.Errorf("Error checking git status: %v", err)
    }
    if status == "" {
        warn("No changes to commit.\n")
        return nil
    }

    _, err = runCommand("git", "commit", "-m", commitMsg)
    if err != nil {
        return fmt.Errorf("Error committing changes: %v", err)
    }
    success("Committed changes with message:\n%s\n", commitMsg)

    branch, err := runCommand("git", "rev-parse", "--abbrev-ref", "HEAD")
    if err != nil {
        return fmt.Errorf("Error getting current branch: %v", err)
    }
    branch = strings.TrimSpace(branch)

    _, err = runCommand("git", "push", "origin", branch)
    if err != nil {
        return fmt.Errorf("Error pushing changes: %v", err)
    }
    success("Pushed changes to origin/%s\n", branch)

    return nil
}

// Show a loading indicator
func showLoadingIndicator(done chan bool) {
    frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
    i := 0
    for {
        select {
        case <-done:
            fmt.Print("\r")
            return
        default:
            fmt.Printf("\r%s Working...", frames[i])
            i = (i + 1) % len(frames)
            time.Sleep(100 * time.Millisecond)
        }
    }
}

// Read user input with a timeout
func readUserInput(timeout time.Duration) (string, error) {
    inputChan := make(chan string)
    errChan := make(chan error)
    go func() {
        var userInput string
        _, err := fmt.Scanln(&userInput)
        if err != nil {
            errChan <- err
            return
        }
        inputChan <- userInput
    }()

    select {
    case <-time.After(timeout):
        return "", fmt.Errorf("Input timed out after %v", timeout)
    case err := <-errChan:
        return "", err
    case input := <-inputChan:
        return input, nil
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

    // Create a detailed change summary
    changeSummary := generateChangeSummary(diff)

    // Generate commit message
    commitMsg, commitErr := generateCommitMessage(changeSummary)
    if commitErr != nil {
        done <- true
        errorLog("Error generating commit message: %v\n", commitErr)
        return
    }

    done <- true

    // Proceed with git commit and push
    err = gitCommitAndPush(commitMsg)
    if err != nil {
        errorLog("Error in git operations: %v\n", err)
        return
    }

    success("\ngitdone completed successfully.\n")
}

// Generate a detailed change summary
func generateChangeSummary(diff string) string {
    var summary strings.Builder

    summary.WriteString("The code changes involve:\n")

    // Get list of modified files
    modifiedFiles := extractModifiedFiles(diff)
    if len(modifiedFiles) > 0 {
        summary.WriteString("- Modifications to the following files: ")
        summary.WriteString(strings.Join(modifiedFiles, ", "))
        summary.WriteString(".\n")
    }

    // Add a general description (you can customize this)
    summary.WriteString("- Improvements to commit message generation logic.\n")

    return summary.String()
}

// Extract modified files from diff
func extractModifiedFiles(diff string) []string {
    modifiedFiles := make(map[string]bool)
    scanner := bufio.NewScanner(strings.NewReader(diff))
    for scanner.Scan() {
        line := scanner.Text()
        if strings.HasPrefix(line, "diff --git ") {
            parts := strings.Split(line, " ")
            if len(parts) >= 4 {
                aFile := parts[2]
                // Remove 'a/' prefix
                aFile = strings.TrimPrefix(aFile, "a/")
                modifiedFiles[aFile] = true
            }
        }
    }
    fileList := make([]string, 0, len(modifiedFiles))
    for file := range modifiedFiles {
        fileList = append(fileList, file)
    }
    return fileList
}
