package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
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
    maxConcurrentOperations = 4
)

// Run a shell command and return the output
func runCommand(name string, args ...string) (string, error) {
    if runtime.GOOS == "windows" {
        // Handle Git paths on Windows
        if name == "git" {
            name = findGitExecutable()
        }
    }

    cmd := exec.Command(name, args...)
    var out bytes.Buffer
    var stderr bytes.Buffer
    cmd.Stdout = &out
    cmd.Stderr = &stderr
    
    // Set working directory
    cmd.Dir, _ = os.Getwd()

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
        "temperature": 0.2,
        "stream":      true,
    }

    jsonBody, err := json.Marshal(requestBody)
    if err != nil {
        return "", fmt.Errorf("Error marshaling request body: %v", err)
    }

    // Create a client with custom timeout and keep-alive settings
    client := &http.Client{
        Timeout: timeout,
        Transport: &http.Transport{
            MaxIdleConns:        100,
            MaxIdleConnsPerHost: 100,
            IdleConnTimeout:     90 * time.Second,
        },
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

        resp, err := client.Do(req)
        if err != nil {
            if attempt < maxRetries {
                time.Sleep(time.Duration(attempt) * time.Second)
                continue
            }
            return "", err
        }
        defer resp.Body.Close()

        if resp.StatusCode != http.StatusOK {
            if attempt < maxRetries {
                time.Sleep(time.Duration(attempt) * time.Second)
                continue
            }
            return "", fmt.Errorf("API returned status code: %d", resp.StatusCode)
        }

        reader := bufio.NewReader(resp.Body)
        var fullResponse strings.Builder

        for {
            line, err := reader.ReadString('\n')
            if err != nil {
                if err == io.EOF {
                    break
                }
                return "", fmt.Errorf("Error reading response: %v", err)
            }

            var ollamaResp map[string]interface{}
            if err := json.Unmarshal([]byte(line), &ollamaResp); err != nil {
                continue
            }

            if response, ok := ollamaResp["response"].(string); ok {
                fullResponse.WriteString(response)
            }

            if done, ok := ollamaResp["done"].(bool); ok && done {
                break
            }
        }

        responseText = strings.TrimSpace(fullResponse.String())
        if responseText != "" {
            break
        }
    }

    if responseText == "" {
        return "", fmt.Errorf("Failed to get a valid response after %d attempts", maxRetries)
    }

    return responseText, nil
}

// Clean the commit message by removing unwanted phrases
func cleanCommitMessage(msg string) string {
    msg = strings.TrimSpace(msg)

    // Remove AI-like phrases and formalities
    unwantedPhrases := []string{
        `(?i)here'?s?(?:\sa)?(?:\spossible)?(?:\ssuggested)?`,
        `(?i)I would suggest`,
        `(?i)let me know`,
        `(?i)you can use`,
        `(?i)hope this helps`,
        `(?i)please let me know`,
        `(?i)I recommend`,
        `(?i)I have`,
        `(?i)I think`,
        `(?i)we can`,
        `(?i)this commit`,
        `(?i)the commit message`,
        `(?i)this message`,
        `(?i):\s*$`,
        `(?i)^"`,
        `(?i)"$`,
        `(?i)thanks`,
        `(?i)hello`,
        `(?i)hi\s`,
    }

    for _, phrase := range unwantedPhrases {
        re := regexp.MustCompile(phrase)
        msg = re.ReplaceAllString(msg, "")
    }

    // Remove quotes and extra whitespace
    msg = strings.Trim(msg, `"' \n`)
    msg = strings.TrimSpace(msg)

    // Ensure first letter is uppercase
    if len(msg) > 0 {
        msg = strings.ToUpper(msg[:1]) + msg[1:]
    }

    // Remove any remaining colons at the end
    msg = strings.TrimRight(msg, ":")

    return msg
}

// Generate commit message using Ollama API
func generateCommitMessage(changeSummary string) (string, error) {
    info("Generating commit message using Ollama API...\n")
    prompt := fmt.Sprintf(`Analyze these code changes and write a git commit message that:
1. Starts with a verb in present tense
2. Describes the technical change made to the code
3. Is under 72 characters
4. Only includes what was changed in the code
5. Format: <verb> <technical component> <specific change>

Example good messages:
- "Add error handling to file upload function"
- "Fix SQL query performance in user search"
- "Update JWT token validation logic"
- "Refactor authentication middleware"

Example bad messages:
- "Made some changes to the code"
- "Updated files"
- "Fixed a bug"
- "Improved performance"

Code changes to analyze:
%s`, changeSummary)

    commitMsg, err := callOllamaAPI(prompt)
    if err != nil {
        return "", err
    }

    commitMsg = cleanCommitMessage(commitMsg)

    if len(commitMsg) == 0 {
        return "", fmt.Errorf("Generated commit message is empty")
    }

    return formatCommitMessage(commitMsg), nil
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

// Add helper function to find Git executable on Windows
func findGitExecutable() string {
    // Common Git installation paths on Windows
    commonPaths := []string{
        filepath.Join(os.Getenv("ProgramFiles"), "Git", "cmd", "git.exe"),
        filepath.Join(os.Getenv("ProgramFiles(x86)"), "Git", "cmd", "git.exe"),
        filepath.Join(os.Getenv("LocalAppData"), "Programs", "Git", "cmd", "git.exe"),
    }

    // First check if git is in PATH
    if path, err := exec.LookPath("git"); err == nil {
        return path
    }

    // Check common installation paths
    for _, path := range commonPaths {
        if _, err := os.Stat(path); err == nil {
            return path
        }
    }

    // Default to "git" and let the system handle it
    return "git"
}

// Add error handling utility
func handleError(err error, message string) {
    if err != nil {
        errorLog("%s: %v\n", message, err)
        os.Exit(1)
    }
}

func main() {
    info("Starting gitdone...\n")

    // Ensure we're in a git repository
    if _, err := runCommand("git", "rev-parse", "--git-dir"); err != nil {
        errorLog("Not in a git repository\n")
        return
    }

    done := make(chan bool)
    go showLoadingIndicator(done)

    // Create error channel for goroutine error handling
    errChan := make(chan error, 1)

    go func() {
        if err := addAllChanges(); err != nil {
            errChan <- err
            return
        }

        diff, err := getGitDiff()
        if err != nil {
            errChan <- err
            return
        }

        if diff == "" {
            errChan <- fmt.Errorf("no changes to commit")
            return
        }

        changeSummary := generateChangeSummary(diff)
        commitMsg, err := generateCommitMessage(changeSummary)
        if err != nil {
            errChan <- err
            return
        }

        if err := gitCommitAndPush(commitMsg); err != nil {
            errChan <- err
            return
        }

        errChan <- nil
    }()

    // Wait for either an error or completion
    select {
    case err := <-errChan:
        done <- true
        if err != nil {
            if err.Error() == "no changes to commit" {
                warn("No changes to commit.\n")
            } else {
                errorLog("Error: %v\n", err)
            }
            return
        }
        success("\ngitdone completed successfully.\n")
    case <-time.After(timeout):
        done <- true
        errorLog("Operation timed out\n")
        return
    }
}

// Generate a detailed change summary
func generateChangeSummary(diff string) string {
    var summary strings.Builder
    
    // Extract file changes
    files := extractModifiedFiles(diff)
    if len(files) > 0 {
        summary.WriteString("Files changed:\n")
        for _, file := range files {
            summary.WriteString(fmt.Sprintf("* %s\n", file))
        }
        summary.WriteString("\n")
    }
    
    // Parse the diff for actual changes
    scanner := bufio.NewScanner(strings.NewReader(diff))
    var currentFile string
    changes := make(map[string][]string)
    
    for scanner.Scan() {
        line := scanner.Text()
        
        if strings.HasPrefix(line, "diff --git") {
            parts := strings.Split(line, " ")
            if len(parts) >= 4 {
                currentFile = strings.TrimPrefix(parts[2], "a/")
                changes[currentFile] = []string{}
            }
            continue
        }
        
        // Focus on function and structural changes
        if strings.HasPrefix(line, "+") && !strings.HasPrefix(line, "+++") {
            line = strings.TrimPrefix(line, "+")
            line = strings.TrimSpace(line)
            if line != "" {
                // Identify important code changes
                if strings.HasPrefix(line, "func ") ||
                   strings.HasPrefix(line, "type ") ||
                   strings.HasPrefix(line, "var ") ||
                   strings.HasPrefix(line, "const ") ||
                   strings.Contains(line, "struct") ||
                   strings.Contains(line, "interface") ||
                   strings.Contains(line, "return ") ||
                   strings.Contains(line, "if ") {
                    changes[currentFile] = append(changes[currentFile], fmt.Sprintf("Added: %s", line))
                }
            }
        } else if strings.HasPrefix(line, "-") && !strings.HasPrefix(line, "---") {
            line = strings.TrimPrefix(line, "-")
            line = strings.TrimSpace(line)
            if line != "" {
                // Identify important code changes
                if strings.HasPrefix(line, "func ") ||
                   strings.HasPrefix(line, "type ") ||
                   strings.HasPrefix(line, "var ") ||
                   strings.HasPrefix(line, "const ") ||
                   strings.Contains(line, "struct") ||
                   strings.Contains(line, "interface") ||
                   strings.Contains(line, "return ") ||
                   strings.Contains(line, "if ") {
                    changes[currentFile] = append(changes[currentFile], fmt.Sprintf("Removed: %s", line))
                }
            }
        }
    }
    
    // Build a technical summary
    summary.WriteString("Technical changes:\n")
    for file, fileChanges := range changes {
        if len(fileChanges) > 0 {
            summary.WriteString(fmt.Sprintf("\nIn %s:\n", file))
            for _, change := range fileChanges {
                summary.WriteString(fmt.Sprintf("* %s\n", change))
            }
        }
    }
    
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
