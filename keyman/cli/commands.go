package cli

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

func GetCommands() map[string]Command {
	return map[string]Command{
		"status": {
			Name:        "status",
			Description: "Show SSH key status and security audit",
			Action:      Status,
		},
		"view": {
			Name:        "view",
			Description: "View your public SSH key",
			Action:      ViewKey,
		},
		"init": {
			Name:        "init",
			Description: "Initialize SSH key configuration",
			Action:      Setup,
		},
		"reset": {
			Name:        "reset",
			Description: "Remove all SSH keys and create new secure key",
			Action:      Reset,
		},
		"rotate": {
			Name:        "rotate",
			Description: "Rotate SSH key and update configured services",
			Action:      Rotate,
		},
		"test-notify": {
			Name:        "test-notify",
			Description: "Test the notification system",
			Action:      TestNotifications,
		},
		"scanner": {
			Name:        "scanner",
			Description: "Control the security scanner service",
			Action:      ScannerControl,
		},
		"key": {
			Name:        "key",
			Description: "Manage SSH keys (add, modify, encrypt, change password)",
			Action:      KeyManagement,
		},
		"agent": {
			Name:        "agent",
			Description: "Manage SSH agent (start, stop, add, remove keys)",
			Action:      AgentControl,
		},
		"audit": {
			Name:        "audit",
			Description: "Run comprehensive security audit and fix issues",
			Action:      RunAudit,
		},
		"rotation": {
			Name:        "rotation",
			Description: "Configure key rotation settings",
			Action:      ConfigureRotation,
		},
	}
}

func Status() error {
	scanner := NewSecurityScanner()
	findings := scanner.RunScan()

	// Get SSH key info
	homeDir, _ := os.UserHomeDir()
	keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")

	if keyInfo, err := scanner.GetKeyInfo(keyPath); err == nil {
		fmt.Println("SSH Key Status:")
		fmt.Printf("Location: %s\n", keyInfo.Path)
		fmt.Printf("Type: %s (%d bits)\n", keyInfo.Type, keyInfo.Bits)
		fmt.Printf("Password: %s\n", keyInfo.PasswordStatus)
		fmt.Printf("Comment: %s\n", keyInfo.Comment)
		fmt.Printf("Created: %s\n", keyInfo.CreatedAt.Format("2006-01-02 15:04:05"))

		// Add rotation status
		configPath := filepath.Join(homeDir, ".config", "keyman", "config")
		if content, err := os.ReadFile(configPath); err == nil {
			var interval, lastRotation string
			lines := strings.Split(string(content), "\n")
			for _, line := range lines {
				if strings.HasPrefix(line, "rotation_interval=") {
					interval = strings.TrimPrefix(line, "rotation_interval=")
				} else if strings.HasPrefix(line, "last_rotation=") {
					lastRotation = strings.TrimPrefix(line, "last_rotation=")
				}
			}

			if interval != "" && lastRotation != "" {
				last, _ := time.Parse("2006-01-02", lastRotation)
				days, _ := strconv.Atoi(interval)
				nextRotation := last.AddDate(0, 0, days)
				daysUntilRotation := int(time.Until(nextRotation).Hours() / 24)

				fmt.Println("\nRotation Settings:")
				fmt.Printf("Interval: Every %s days\n", interval)
				fmt.Printf("Last Rotation: %s\n", lastRotation)
				fmt.Printf("Next Rotation: %s", nextRotation.Format("2006-01-02"))

				if daysUntilRotation <= 7 {
					fmt.Printf(" (⚠️  %d days remaining)", daysUntilRotation)
					NotifyRotationNeeded(daysUntilRotation)
				} else {
					fmt.Printf(" (%d days remaining)", daysUntilRotation)
				}
				fmt.Println()
			}
		}
		fmt.Println()
	}

	// Add audit information
	auditFile := filepath.Join(homeDir, ".config", "keyman", "audit", "usage.log")
	if content, err := os.ReadFile(auditFile); err == nil {
		lines := strings.Split(string(content), "\n")

		fmt.Println("\nRecent Key Usage:")
		count := 0
		for i := len(lines) - 2; i >= 0 && count < 5; i-- {
			if strings.TrimSpace(lines[i]) != "" {
				fmt.Printf("  %s\n", lines[i])
				count++
			}
		}
	}

	if len(findings) == 0 {
		fmt.Println("✅ All SSH keys are properly configured and secure")
		return nil
	}

	fmt.Printf("Found %d security issues:\n\n", len(findings))

	// Group findings by severity
	var high, medium, low []SecurityFinding
	for _, finding := range findings {
		switch finding.Severity {
		case "high":
			high = append(high, finding)
		case "medium":
			medium = append(medium, finding)
		case "low":
			low = append(low, finding)
		}
	}

	// Print findings by severity
	if len(high) > 0 {
		fmt.Println("🔴 High Severity Issues:")
		printFindings(high)
	}
	if len(medium) > 0 {
		fmt.Println("🟡 Medium Severity Issues:")
		printFindings(medium)
	}
	if len(low) > 0 {
		fmt.Println("🔵 Low Severity Issues:")
		printFindings(low)
	}

	checkRotationStatus()

	return nil
}

func printFindings(findings []SecurityFinding) {
	for i, finding := range findings {
		fmt.Printf("%d. %s\n", i+1, finding.Description)
		fmt.Printf("   Path: %s\n", finding.Path)
		fmt.Printf("   Type: %s\n\n", finding.Type)
	}
}

func ViewKey() error {
	homeDir, _ := os.UserHomeDir()
	pubKeyPath := filepath.Join(homeDir, ".ssh", "id_rsa.pub")

	// Check if public key exists
	if _, err := os.Stat(pubKeyPath); err != nil {
		return fmt.Errorf("no SSH key found. Use 'keyman add' to generate one")
	}

	// Display the public key
	fmt.Println("Your public SSH key:")
	pubKey, err := os.ReadFile(pubKeyPath)
	if err != nil {
		return fmt.Errorf("failed to read public key: %v", err)
	}
	fmt.Println(string(pubKey))

	fmt.Println("\nNote: This is your public key which is safe to share.")
	fmt.Println("You can use this key to authenticate with services like GitHub, GitLab, etc.")
	return nil
}

func AddKey() error {
	reader := bufio.NewReader(os.Stdin)

	fmt.Print("Enter a password to protect your SSH key: ")
	password, _ := reader.ReadString('\n')
	password = strings.TrimSpace(password)

	if password == "" {
		return fmt.Errorf("password cannot be empty")
	}

	homeDir, _ := os.UserHomeDir()
	keyPath := fmt.Sprintf("%s/.ssh/id_rsa", homeDir)

	// Generate SSH key with password
	cmd := exec.Command("ssh-keygen",
		"-t", "rsa",
		"-b", "4096",
		"-f", keyPath,
		"-N", password)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to generate key: %v\n%s", err, output)
	}

	fmt.Println("SSH key generated successfully with password protection!")
	return nil
}

func Reset() error {
	homeDir, _ := os.UserHomeDir()
	sshDir := filepath.Join(homeDir, ".ssh")

	fmt.Println("⚠️  SSH Key Reset")
	fmt.Println("This will:")
	fmt.Println("1. Remove all existing SSH keys")
	fmt.Println("2. Create a new password-protected key")
	fmt.Println("3. Set proper permissions")
	fmt.Println("4. Add the new key to SSH agent")
	fmt.Print("\n⚠️  Are you sure you want to continue? (y/n): ")

	if !confirmAction() {
		fmt.Println("Reset cancelled.")
		return nil
	}

	// Remove SSH keys from agent first
	fmt.Println("\nRemoving keys from SSH agent...")
	exec.Command("ssh-add", "-D").Run()

	// Remove existing .ssh directory
	fmt.Println("Removing existing SSH keys...")
	if err := os.RemoveAll(sshDir); err != nil {
		return fmt.Errorf("failed to remove old SSH directory: %v", err)
	}

	// Create new .ssh directory
	fmt.Println("Creating new SSH directory...")
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		return fmt.Errorf("failed to create SSH directory: %v", err)
	}

	// Generate new key
	fmt.Println("\nGenerating new SSH key...")
	keyPath := filepath.Join(sshDir, "id_rsa")

	// Get username and hostname for the comment
	username := os.Getenv("USERNAME")
	if username == "" {
		username = os.Getenv("USER")
	}
	hostname, _ := os.Hostname()
	comment := fmt.Sprintf("%s@%s", username, hostname)

	fmt.Println("You must set a password to protect your new key.")
	cmd := exec.Command("ssh-keygen",
		"-t", "rsa",
		"-b", "4096",
		"-f", keyPath,
		"-C", comment)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to generate new key: %v", err)
	}

	// Set proper permissions
	if runtime.GOOS != "windows" {
		os.Chmod(keyPath, 0600)
		os.Chmod(keyPath+".pub", 0644)
	} else {
		cmd := exec.Command("icacls", keyPath, "/inheritance:r", "/grant:r", fmt.Sprintf("%s:F", os.Getenv("USERNAME")))
		cmd.Run()
	}

	// Add to SSH agent
	fmt.Println("\nAdding new key to SSH agent...")
	addCmd := exec.Command("ssh-add", keyPath)
	addCmd.Stdin = os.Stdin
	addCmd.Stdout = os.Stdout
	addCmd.Stderr = os.Stderr
	addCmd.Run()

	// Display the public key
	fmt.Println("\nYour new public SSH key (safe to share):")
	pubKey, _ := os.ReadFile(keyPath + ".pub")
	fmt.Println(string(pubKey))

	fmt.Println("\n✅ SSH key reset complete!")
	fmt.Println("Remember to update this key in any services where you used the old key.")
	fmt.Println("You can use 'keyman github' to add it to GitHub.")

	return nil
}

func AddToGitHub() error {
	homeDir, _ := os.UserHomeDir()
	pubKeyPath := fmt.Sprintf("%s/.ssh/id_rsa.pub", homeDir)

	content, err := os.ReadFile(pubKeyPath)
	if err != nil {
		return fmt.Errorf("no SSH key found. Use 'keyman add' to generate one")
	}

	fmt.Println("To add this key to GitHub:")
	fmt.Println("1. Go to https://github.com/settings/ssh/new")
	fmt.Println("2. Add a title for your key")
	fmt.Println("3. Copy and paste this public key:")
	fmt.Println(string(content))

	fmt.Print("\nWould you like to open GitHub SSH settings in your browser? (y/n): ")
	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')

	if strings.ToLower(strings.TrimSpace(response)) == "y" {
		cmd := exec.Command("open", "https://github.com/settings/ssh/new")
		cmd.Run()
	}

	return nil
}

func AddToGitLab() error {
	// Similar to GitHub function
	return nil
}

func Setup() error {
	fmt.Println("Welcome to Keyman SSH Setup!")
	fmt.Println("This will help you set up your SSH keys securely.\n")

	// Create scanner at the start
	scanner := NewSecurityScanner()
	findings := scanner.RunScan()

	// Check for multiple keys first
	var multipleKeys bool
	for _, finding := range findings {
		if finding.Type == "multiple_keys" {
			multipleKeys = true
			fmt.Println("⚠️  WARNING: Multiple SSH keys found on your system:")
			fmt.Println(finding.Description)
			fmt.Println("This is a security risk. It's recommended to use a single key.")
			break
		}
	}
	_ = multipleKeys // Use blank identifier to handle unused variable

	homeDir, _ := os.UserHomeDir()
	sshDir := filepath.Join(homeDir, ".ssh")
	keyPath := filepath.Join(sshDir, "id_rsa")

	// Create .ssh directory if it doesn't exist
	if _, err := os.Stat(sshDir); os.IsNotExist(err) {
		os.MkdirAll(sshDir, 0700)
	}

	hasKey := hasExistingKey(sshDir)
	if hasKey {
		isEncrypted := !hasUnencryptedKey(findings)
		if isEncrypted {
			fmt.Println("✅ Found existing password-protected SSH key.")
			fmt.Print("Would you like to replace it with a new key? (y/n): ")
			if confirmAction() {
				return generateNewKey(keyPath)
			}
		} else {
			fmt.Println("⚠️  Found existing SSH key but it's not password protected!")
			fmt.Println("It's strongly recommended to protect your key with a password.")
			fmt.Print("Would you like to (1) add password to existing key or (2) generate new key? (1/2): ")
			choice := readInput()

			if choice == "1" {
				fmt.Println("\nAdding password protection to existing key...")
				cmd := exec.Command("ssh-keygen", "-p", "-f", keyPath)
				cmd.Stdin = os.Stdin
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				if err := cmd.Run(); err != nil {
					return fmt.Errorf("failed to add password: %v", err)
				}
			} else if choice == "2" {
				return generateNewKey(keyPath)
			} else {
				return fmt.Errorf("invalid choice - key must be password protected")
			}
		}
	} else {
		fmt.Println("No SSH key found. Creating new key...")
		return generateNewKey(keyPath)
	}

	// Display the public key
	fmt.Println("\nYour public SSH key (safe to share):")
	pubKey, _ := os.ReadFile(keyPath + ".pub")
	fmt.Println(string(pubKey))

	// Security notes
	fmt.Println("\nImportant Security Notes:")
	fmt.Println("1. The SSH key password protects the key when it's being used.")
	fmt.Println("2. File system permissions are critical - only you should have read access to the private key.")
	fmt.Println("3. Never share your private key file or commit it to version control.")
	fmt.Println("4. Consider using file system encryption for additional security.")

	// Set proper permissions
	if runtime.GOOS == "windows" {
		cmd := exec.Command("icacls", keyPath, "/inheritance:r", "/grant:r", fmt.Sprintf("%s:F", os.Getenv("USERNAME")))
		cmd.Run()
	} else {
		os.Chmod(keyPath, 0600)
		os.Chmod(keyPath+".pub", 0644)
	}

	// Ask about key rotation
	fmt.Print("\nWould you like to enable automatic key rotation? (y/n): ")
	if confirmAction() {
		fmt.Print("How often would you like to rotate your keys (in days, recommended 90)? ")
		days := readInput()
		interval, err := strconv.Atoi(days)
		if err != nil {
			fmt.Println("Invalid interval, using default of 90 days")
			interval = 90
		}

		settings := RotationSettings{
			Enabled:      true,
			Interval:     interval,
			LastRotation: time.Now(),
		}
		if err := saveRotationSettings(settings); err != nil {
			fmt.Println("Warning: Failed to save rotation configuration")
		} else {
			fmt.Printf("Key rotation enabled and set for every %d days\n", interval)
		}
	} else {
		fmt.Println("Key rotation disabled. You can enable it later with: keyman rotation enable")
		settings := RotationSettings{Enabled: false}
		saveRotationSettings(settings)
	}

	fmt.Println("\nSetup complete! Your SSH keys are now configured securely.")
	fmt.Println("You can run 'keyman status' anytime to check your SSH key security status.")

	return nil
}

// Helper function to generate new key
func generateNewKey(keyPath string) error {
	username := os.Getenv("USERNAME")
	if username == "" {
		username = os.Getenv("USER")
	}
	hostname, _ := os.Hostname()
	comment := fmt.Sprintf("%s@%s", username, hostname)

	fmt.Println("\nGenerating new SSH key (you must set a password)...")
	cmd := exec.Command("ssh-keygen",
		"-t", "rsa",
		"-b", "4096",
		"-f", keyPath,
		"-C", comment)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return err
	}

	// Track key generation
	TrackKeyUsage(keyPath, "generated")

	// Send notification
	SendNotification(Notification{
		Title:   "SSH Key Generated",
		Message: "New SSH key has been generated successfully",
		Type:    NotifySuccess,
	})

	return nil
}

func hasMultipleKeys(findings []SecurityFinding) bool {
	for _, f := range findings {
		if f.Type == "multiple_keys" {
			return true
		}
	}
	return false
}

func hasExistingKey(sshDir string) bool {
	_, err := os.Stat(filepath.Join(sshDir, "id_rsa"))
	return err == nil
}

func fixPermissions(findings []SecurityFinding) {
	for _, finding := range findings {
		if finding.Type == "permission" {
			if strings.Contains(finding.Path, "id_rsa.pub") {
				os.Chmod(finding.Path, 0644)
			} else {
				os.Chmod(finding.Path, 0600)
			}
		}
	}
}

func addToAgent() {
	homeDir, _ := os.UserHomeDir()
	keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")
	if err := exec.Command("ssh-add", keyPath).Run(); err == nil {
		NotifyAgentStatus(keyPath, true)
	}
}

func removeFromAgent() {
	homeDir, _ := os.UserHomeDir()
	keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")
	if err := exec.Command("ssh-add", "-d", keyPath).Run(); err == nil {
		NotifyAgentStatus(keyPath, false)
	}
}

func confirmAction() bool {
	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')
	return strings.ToLower(strings.TrimSpace(response)) == "y"
}

func hasUnencryptedKey(findings []SecurityFinding) bool {
	for _, f := range findings {
		if f.Type == "unencrypted" {
			return true
		}
	}
	return false
}

func getOtherSecurityIssues(findings []SecurityFinding) []SecurityFinding {
	var others []SecurityFinding
	for _, f := range findings {
		if f.Type != "unencrypted" {
			others = append(others, f)
		}
	}
	return others
}

func readInput() string {
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	return strings.TrimSpace(input)
}

func getPassword(prompt string) string {
	fmt.Print(prompt)
	password := readInput()
	if password == "" {
		fmt.Println("Password cannot be empty")
		return getPassword(prompt)
	}
	return password
}

func addToAgentSilently() {
	homeDir, _ := os.UserHomeDir()
	keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")
	cmd := exec.Command("ssh-add", keyPath)
	cmd.Run()
}

func Rotate() error {
	fmt.Println("Starting SSH key rotation...")

	// Backup existing key
	homeDir, _ := os.UserHomeDir()
	sshDir := filepath.Join(homeDir, ".ssh")
	keyPath := filepath.Join(sshDir, "id_rsa")
	backupPath := filepath.Join(sshDir, "id_rsa.backup")

	if err := os.Rename(keyPath, backupPath); err != nil {
		return fmt.Errorf("failed to backup existing key: %v", err)
	}

	// Generate new key
	if err := generateNewKey(keyPath); err != nil {
		SendErrorNotification("Key Rotation Failed", err)
		os.Rename(backupPath, keyPath) // Restore backup
		return err
	}

	// Update configured services
	fmt.Println("\nUpdating configured services...")
	// TODO: Implement service updates

	fmt.Println("\n✅ Key rotation complete!")
	fmt.Println("Your old key has been backed up to:", backupPath)
	fmt.Println("Remember to update your key in any services that aren't automatically updated.")

	// Track rotation
	TrackKeyUsage(keyPath, "rotated")

	// Send notification
	SendNotification(Notification{
		Title:   "SSH Key Rotated",
		Message: "Your SSH key has been rotated successfully",
		Type:    NotifySuccess,
	})

	return nil
}

func SendErrorNotification(s string, err error) {
	panic("unimplemented")
}

func checkRotationStatus() {
	configPath := filepath.Join(os.Getenv("HOME"), ".config", "keyman", "config")
	content, err := os.ReadFile(configPath)
	if err != nil {
		return
	}

	var interval, lastRotation string
	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "rotation_interval=") {
			interval = strings.TrimPrefix(line, "rotation_interval=")
		} else if strings.HasPrefix(line, "last_rotation=") {
			lastRotation = strings.TrimPrefix(line, "last_rotation=")
		}
	}

	if interval != "" && lastRotation != "" {
		last, _ := time.Parse("2006-01-02", lastRotation)
		days, _ := strconv.Atoi(interval)
		nextRotation := last.AddDate(0, 0, days)

		if time.Now().After(nextRotation) {
			fmt.Printf("\n⚠️  Key rotation recommended (last rotation: %s)\n", lastRotation)
			fmt.Println("Run 'keyman rotate' to rotate your key")
		}
	}
}

func TestNotifications() error {
	fmt.Println("Testing notification system...")

	// Test info notification
	fmt.Println("1. Sending info notification...")
	SendNotification(Notification{
		Title:    "Info Test",
		Message:  "This is a test info notification",
		Type:     NotifyInfo,
		Duration: 5 * time.Second,
	})
	time.Sleep(2 * time.Second)

	// Test warning notification
	fmt.Println("2. Sending warning notification...")
	SendNotification(Notification{
		Title:    "Warning Test",
		Message:  "This is a test warning notification",
		Type:     NotifyWarning,
		Duration: 5 * time.Second,
	})
	time.Sleep(2 * time.Second)

	// Test error notification
	fmt.Println("3. Sending error notification...")
	SendNotification(Notification{
		Title:    "Error Test",
		Message:  "This is a test error notification",
		Type:     NotifyError,
		Duration: 5 * time.Second,
	})
	time.Sleep(2 * time.Second)

	// Test success notification
	fmt.Println("4. Sending success notification...")
	SendNotification(Notification{
		Title:    "Success Test",
		Message:  "This is a test success notification",
		Type:     NotifySuccess,
		Duration: 5 * time.Second,
	})

	fmt.Println("\nAll test notifications sent!")
	fmt.Println("You should have seen 4 different notifications.")
	fmt.Println("If you didn't see any notifications, there might be an issue with your system's notification settings.")

	return nil
}

func ScannerControl() error {
	if len(os.Args) < 3 {
		fmt.Println("Usage: keyman scanner <command>")
		fmt.Println("Commands:")
		fmt.Println("  status    - Show scanner status")
		fmt.Println("  start     - Start the scanner")
		fmt.Println("  stop      - Stop the scanner")
		fmt.Println("  interval  - Set scan interval (in minutes)")
		return nil
	}

	scanner := GetScannerService()
	command := os.Args[2]

	switch command {
	case "status":
		fmt.Printf("Scanner is %s\n", map[bool]string{true: "running", false: "stopped"}[scanner.isRunning])
		if scanner.isRunning {
			fmt.Printf("Last scan: %s\n", scanner.lastScanAt.Format(time.RFC3339))
			fmt.Printf("Scan interval: %s\n", scanner.interval)
		}

	case "start":
		if err := scanner.Start(); err != nil {
			return fmt.Errorf("failed to start scanner: %v", err)
		}
		fmt.Println("Scanner started successfully")

	case "stop":
		scanner.Stop()
		fmt.Println("Scanner stopped successfully")

	case "interval":
		if len(os.Args) < 4 {
			return fmt.Errorf("please specify interval in minutes")
		}
		minutes, err := strconv.Atoi(os.Args[3])
		if err != nil {
			return fmt.Errorf("invalid interval: %v", err)
		}
		scanner.interval = time.Duration(minutes) * time.Minute
		fmt.Printf("Scan interval set to %d minutes\n", minutes)

	default:
		return fmt.Errorf("unknown scanner command: %s", command)
	}

	return nil
}

func KeyManagement() error {
	if len(os.Args) < 3 {
		fmt.Println("Usage: keyman key <command>")
		fmt.Println("\nCommands:")
		fmt.Println("  encrypt     - Add password protection to an existing key")
		fmt.Println("  password    - Change password of an existing key")
		fmt.Println("  comment     - Change or add comment to a key")
		fmt.Println("  convert     - Convert key to different format (RSA, ED25519, etc)")
		fmt.Println("  fingerprint - Show key fingerprint")
		fmt.Println("  verify      - Verify a private/public key pair")
		return nil
	}

	command := os.Args[2]
	homeDir, _ := os.UserHomeDir()
	keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")

	switch command {
	case "encrypt":
		fmt.Println("Adding password protection to key...")
		cmd := exec.Command("ssh-keygen", "-p", "-f", keyPath)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to encrypt key: %v", err)
		}
		SendNotification(Notification{
			Title:   "SSH Key Encrypted",
			Message: "Password protection added successfully",
			Type:    NotifySuccess,
		})

	case "password":
		fmt.Println("Changing key password...")
		cmd := exec.Command("ssh-keygen", "-p", "-f", keyPath)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to change password: %v", err)
		}
		SendNotification(Notification{
			Title:   "Password Changed",
			Message: "SSH key password updated successfully",
			Type:    NotifySuccess,
		})

	case "comment":
		if len(os.Args) < 4 {
			return fmt.Errorf("please provide a comment")
		}
		comment := os.Args[3]
		cmd := exec.Command("ssh-keygen", "-c", "-f", keyPath, "-C", comment)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to change comment: %v", err)
		}
		SendNotification(Notification{
			Title:   "Comment Updated",
			Message: "SSH key comment changed successfully",
			Type:    NotifySuccess,
		})

	case "convert":
		if len(os.Args) < 4 {
			fmt.Println("Available key types:")
			fmt.Println("  rsa     - RSA (2048-8192 bits)")
			fmt.Println("  ed25519 - ED25519 (recommended)")
			fmt.Println("  ecdsa   - ECDSA")
			return nil
		}
		keyType := os.Args[3]
		newKeyPath := keyPath + ".new"

		var cmd *exec.Cmd
		switch keyType {
		case "rsa":
			cmd = exec.Command("ssh-keygen", "-t", "rsa", "-b", "4096", "-f", newKeyPath)
		case "ed25519":
			cmd = exec.Command("ssh-keygen", "-t", "ed25519", "-f", newKeyPath)
		case "ecdsa":
			cmd = exec.Command("ssh-keygen", "-t", "ecdsa", "-b", "384", "-f", newKeyPath)
		default:
			return fmt.Errorf("unsupported key type: %s", keyType)
		}

		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to convert key: %v", err)
		}

		// Backup old key
		os.Rename(keyPath, keyPath+".backup")
		os.Rename(keyPath+".pub", keyPath+".pub.backup")

		// Move new key into place
		os.Rename(newKeyPath, keyPath)
		os.Rename(newKeyPath+".pub", keyPath+".pub")

		SendNotification(Notification{
			Title:   "Key Converted",
			Message: fmt.Sprintf("SSH key converted to %s format", keyType),
			Type:    NotifySuccess,
		})

	case "fingerprint":
		cmd := exec.Command("ssh-keygen", "-l", "-f", keyPath)
		output, err := cmd.Output()
		if err != nil {
			return fmt.Errorf("failed to get fingerprint: %v", err)
		}
		fmt.Printf("Key fingerprint: %s", output)

	case "verify":
		fmt.Println("Verifying private/public key pair...")
		// Get public key from private key
		cmd := exec.Command("ssh-keygen", "-y", "-f", keyPath)
		generatedPub, err := cmd.Output()
		if err != nil {
			return fmt.Errorf("failed to read private key: %v", err)
		}

		// Read actual public key
		pubKey, err := os.ReadFile(keyPath + ".pub")
		if err != nil {
			return fmt.Errorf("failed to read public key: %v", err)
		}

		// Compare (ignoring comments)
		genParts := strings.Fields(string(generatedPub))
		pubParts := strings.Fields(string(pubKey))
		if genParts[0] == pubParts[0] && genParts[1] == pubParts[1] {
			fmt.Println("✅ Key pair verification successful")
		} else {
			return fmt.Errorf("❌ key pair verification failed - keys do not match")
		}

	default:
		return fmt.Errorf("unknown key command: %s", command)
	}

	return nil
}

func AgentControl() error {
	if len(os.Args) < 3 {
		fmt.Println("Usage: keyman agent <command>")
		fmt.Println("\nCommands:")
		fmt.Println("  status    - Show SSH agent status")
		fmt.Println("  start     - Start SSH agent")
		fmt.Println("  add       - Add key to agent (cache password)")
		fmt.Println("  remove    - Remove key from agent")
		fmt.Println("  clear     - Remove all keys from agent")
		return nil
	}

	command := os.Args[2]
	scanner := NewSecurityScanner()

	switch command {
	case "status":
		// Check if agent is running
		if runtime.GOOS == "windows" {
			cmd := exec.Command("powershell", "-Command", "Get-Service ssh-agent")
			output, err := cmd.Output()
			if err != nil {
				return fmt.Errorf("failed to get agent status: %v", err)
			}
			fmt.Printf("SSH Agent Status: %s", output)

			// List cached keys
			listCmd := exec.Command("ssh-add", "-l")
			listCmd.Stdout = os.Stdout
			listCmd.Run()
		} else {
			if os.Getenv("SSH_AUTH_SOCK") == "" {
				fmt.Println("SSH Agent Status: Not running")
			} else {
				fmt.Println("SSH Agent Status: Running")
				// List cached keys
				listCmd := exec.Command("ssh-add", "-l")
				listCmd.Stdout = os.Stdout
				listCmd.Run()
			}
		}

	case "start":
		if err := scanner.ensureSSHAgentRunning(); err != nil {
			return fmt.Errorf("failed to start SSH agent: %v", err)
		}
		fmt.Println("SSH agent started successfully")
		fmt.Println("You can now add keys using: keyman agent add")

	case "add":
		homeDir, _ := os.UserHomeDir()
		keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")
		fmt.Println("Adding key to agent (you'll need to enter password once)...")
		cmd := exec.Command("ssh-add", keyPath)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to add key: %v", err)
		}
		fmt.Println("Key added successfully - password will be cached for this session")
		NotifyAgentStatus(keyPath, true)

	case "remove":
		homeDir, _ := os.UserHomeDir()
		keyPath := filepath.Join(homeDir, ".ssh", "id_rsa")
		cmd := exec.Command("ssh-add", "-d", keyPath)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to remove key: %v", err)
		}
		fmt.Println("Key removed from agent - password caching disabled")
		NotifyAgentStatus(keyPath, false)

	case "clear":
		cmd := exec.Command("ssh-add", "-D")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to clear agent: %v", err)
		}
		fmt.Println("All keys removed from agent")
		fmt.Println("Password caching disabled for all keys")

	default:
		return fmt.Errorf("unknown agent command: %s", command)
	}

	return nil
}

func RunAudit() error {
	fmt.Println("🔍 Running comprehensive SSH key audit...")

	homeDir, _ := os.UserHomeDir()
	sshDir := filepath.Join(homeDir, ".ssh")
	configDir := filepath.Join(homeDir, ".config", "keyman")
	configPath := filepath.Join(configDir, "config")
	_ = configPath

	// 1. Check SSH directory structure
	fmt.Println("\n📁 Checking SSH directory structure:")
	if _, err := os.Stat(sshDir); os.IsNotExist(err) {
		fmt.Println("❌ SSH directory not found")
	} else {
		fmt.Printf("✅ SSH directory found: %s\n", sshDir)
	}

	// 2. List all SSH keys
	fmt.Println("\n🔑 SSH Keys Found:")
	keys, _ := filepath.Glob(filepath.Join(sshDir, "id_*"))
	for _, key := range keys {
		if !strings.HasSuffix(key, ".pub") {
			info, err := os.Stat(key)
			if err != nil {
				continue
			}

			// Get key details
			cmd := exec.Command("ssh-keygen", "-l", "-f", key)
			output, _ := cmd.Output()
			keyType := "unknown"
			if len(output) > 0 {
				parts := strings.Fields(string(output))
				if len(parts) > 1 {
					keyType = parts[1]
				}
			}

			fmt.Printf("\nKey: %s\n", filepath.Base(key))
			fmt.Printf("  Type: %s\n", keyType)
			fmt.Printf("  Created: %s\n", info.ModTime().Format("2006-01-02 15:04:05"))
			fmt.Printf("  Size: %d bytes\n", info.Size())

			// Check encryption
			if isKeyEncrypted(key) {
				fmt.Println("  Status: 🔒 Password protected")
			} else {
				fmt.Println("  Status: ⚠️  Not password protected")
			}

			// Check usage
			lastUsed := getLastKeyUsage(key)
			if lastUsed != nil {
				fmt.Printf("  Last Used: %s\n", lastUsed.Format("2006-01-02 15:04:05"))
			} else {
				fmt.Println("  Last Used: Never or unknown")
			}
		}
	}

	// 3. Check key rotation status
	fmt.Println("\n🔄 Key Rotation Status:")
	if content, err := os.ReadFile(filepath.Join(configDir, "config")); err == nil {
		var interval, lastRotation string
		lines := strings.Split(string(content), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "rotation_interval=") {
				interval = strings.TrimPrefix(line, "rotation_interval=")
			} else if strings.HasPrefix(line, "last_rotation=") {
				lastRotation = strings.TrimPrefix(line, "last_rotation=")
			}
		}

		if interval != "" && lastRotation != "" {
			last, _ := time.Parse("2006-01-02", lastRotation)
			days, _ := strconv.Atoi(interval)
			nextRotation := last.AddDate(0, 0, days)
			daysUntil := int(time.Until(nextRotation).Hours() / 24)

			fmt.Printf("Rotation Interval: Every %s days\n", interval)
			fmt.Printf("Last Rotation: %s\n", lastRotation)
			fmt.Printf("Next Rotation: %s (%d days remaining)\n",
				nextRotation.Format("2006-01-02"), daysUntil)
		} else {
			fmt.Println("❌ Key rotation not configured")
		}
	}

	// 4. Check SSH agent status
	fmt.Println("\n🔐 SSH Agent Status:")
	if runtime.GOOS == "windows" {
		cmd := exec.Command("powershell", "-Command", "Get-Service ssh-agent")
		output, _ := cmd.Output()
		if strings.Contains(string(output), "Running") {
			fmt.Println("✅ SSH Agent is running")
			// List cached keys
			listCmd := exec.Command("ssh-add", "-l")
			if output, err := listCmd.Output(); err == nil {
				fmt.Println("Cached keys:")
				fmt.Println(string(output))
			}
		} else {
			fmt.Println("❌ SSH Agent is not running")
		}
	} else {
		if os.Getenv("SSH_AUTH_SOCK") != "" {
			fmt.Println("✅ SSH Agent is running")
			// List cached keys
			listCmd := exec.Command("ssh-add", "-l")
			if output, err := listCmd.Output(); err == nil {
				fmt.Println("Cached keys:")
				fmt.Println(string(output))
			}
		} else {
			fmt.Println("❌ SSH Agent is not running")
		}
	}

	// 5. Check for unused or expired keys
	fmt.Println("\n⏰ Key Usage Analysis:")
	for _, key := range keys {
		if !strings.HasSuffix(key, ".pub") {
			lastUsed := getLastKeyUsage(key)
			if lastUsed == nil {
				fmt.Printf("⚠️  Key never used: %s\n", filepath.Base(key))
			} else if time.Since(*lastUsed) > 90*24*time.Hour {
				fmt.Printf("⚠️  Key not used in 90 days: %s\n", filepath.Base(key))
			}
		}
	}

	// 6. Check permissions and fix if needed
	fmt.Println("\n🔒 Permission Check:")
	scanner := NewSecurityScanner()
	findings := scanner.RunScan()

	if len(findings) > 0 {
		fmt.Printf("Found %d security issues:\n", len(findings))
		for _, finding := range findings {
			fmt.Printf("⚠️  %s\n", finding.Description)
			if finding.Type == "permission" {
				fmt.Printf("   Fixing permissions for: %s\n", finding.Path)
				if strings.HasSuffix(finding.Path, ".pub") {
					os.Chmod(finding.Path, 0644)
				} else {
					os.Chmod(finding.Path, 0600)
				}
			}
		}
	} else {
		fmt.Println("✅ All permissions are correct")
	}

	// 7. Check config file
	fmt.Println("\n📝 SSH Config Check:")
	configPath = filepath.Join(sshDir, "config")
	if _, err := os.Stat(configPath); err == nil {
		fmt.Println("✅ SSH config file found")
		// TODO: Add config file validation
	} else {
		fmt.Println("ℹ️  No SSH config file found")
	}

	return nil
}

func getLastKeyUsage(keyPath string) *time.Time {
	homeDir, _ := os.UserHomeDir()
	auditFile := filepath.Join(homeDir, ".config", "keyman", "audit", "usage.log")

	content, err := os.ReadFile(auditFile)
	if err != nil {
		return nil
	}

	lines := strings.Split(string(content), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.Contains(lines[i], keyPath) {
			timeStr := strings.Split(strings.Trim(lines[i], "[]"), "]")[0]
			if t, err := time.Parse(time.RFC3339, timeStr); err == nil {
				return &t
			}
		}
	}

	return nil
}

func ConfigureRotation() error {
	if len(os.Args) < 3 {
		fmt.Println("Usage: keyman rotation <command>")
		fmt.Println("\nCommands:")
		fmt.Println("  status     - Show rotation settings")
		fmt.Println("  enable     - Enable automatic rotation")
		fmt.Println("  disable    - Disable automatic rotation")
		fmt.Println("  interval   - Set rotation interval (in days)")
		return nil
	}

	command := os.Args[2]
	homeDir, _ := os.UserHomeDir()
	configDir := filepath.Join(homeDir, ".config", "keyman")
	configPath := filepath.Join(configDir, "config")
	_ = configPath // Suppress unused variable error

	switch command {
	case "status":
		settings := loadRotationSettings()
		if !settings.Enabled {
			fmt.Println("Key rotation is disabled")
			return nil
		}
		fmt.Printf("Key rotation is enabled\n")
		fmt.Printf("Interval: %d days\n", settings.Interval)
		fmt.Printf("Last rotation: %s\n", settings.LastRotation.Format("2006-01-02"))
		nextRotation := settings.LastRotation.AddDate(0, 0, settings.Interval)
		daysUntil := int(time.Until(nextRotation).Hours() / 24)
		fmt.Printf("Next rotation: %s (%d days remaining)\n",
			nextRotation.Format("2006-01-02"), daysUntil)

	case "enable":
		settings := loadRotationSettings()
		settings.Enabled = true
		if settings.Interval == 0 {
			settings.Interval = 90 // Default to 90 days
		}
		if settings.LastRotation.IsZero() {
			settings.LastRotation = time.Now()
		}
		if err := saveRotationSettings(settings); err != nil {
			return fmt.Errorf("failed to enable rotation: %v", err)
		}
		fmt.Println("Key rotation enabled")
		fmt.Printf("Keys will be rotated every %d days\n", settings.Interval)

	case "disable":
		settings := loadRotationSettings()
		settings.Enabled = false
		if err := saveRotationSettings(settings); err != nil {
			return fmt.Errorf("failed to disable rotation: %v", err)
		}
		fmt.Println("Key rotation disabled")

	case "interval":
		if len(os.Args) < 4 {
			return fmt.Errorf("please specify interval in days")
		}
		days, err := strconv.Atoi(os.Args[3])
		if err != nil {
			return fmt.Errorf("invalid interval: %v", err)
		}
		settings := loadRotationSettings()
		settings.Interval = days
		if err := saveRotationSettings(settings); err != nil {
			return fmt.Errorf("failed to set interval: %v", err)
		}
		fmt.Printf("Rotation interval set to %d days\n", days)

	default:
		return fmt.Errorf("unknown rotation command: %s", command)
	}

	return nil
}

type RotationSettings struct {
	Enabled      bool
	Interval     int
	LastRotation time.Time
}

func loadRotationSettings() RotationSettings {
	homeDir, _ := os.UserHomeDir()
	configPath := filepath.Join(homeDir, ".config", "keyman", "config")

	settings := RotationSettings{
		Enabled:      false,
		Interval:     90,
		LastRotation: time.Now(),
	}

	content, err := os.ReadFile(configPath)
	if err != nil {
		return settings
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "rotation_enabled=") {
			settings.Enabled = strings.TrimPrefix(line, "rotation_enabled=") == "true"
		} else if strings.HasPrefix(line, "rotation_interval=") {
			if interval, err := strconv.Atoi(strings.TrimPrefix(line, "rotation_interval=")); err == nil {
				settings.Interval = interval
			}
		} else if strings.HasPrefix(line, "last_rotation=") {
			if t, err := time.Parse("2006-01-02", strings.TrimPrefix(line, "last_rotation=")); err == nil {
				settings.LastRotation = t
			}
		}
	}

	return settings
}

func saveRotationSettings(settings RotationSettings) error {
	homeDir, _ := os.UserHomeDir()
	configDir := filepath.Join(homeDir, ".config", "keyman")
	os.MkdirAll(configDir, 0700)

	config := fmt.Sprintf("rotation_enabled=%v\nrotation_interval=%d\nlast_rotation=%s\n",
		settings.Enabled,
		settings.Interval,
		settings.LastRotation.Format("2006-01-02"))

	return os.WriteFile(filepath.Join(configDir, "config"), []byte(config), 0600)
}
