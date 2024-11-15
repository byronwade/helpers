package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Event types
const (
	// Security notifications
	NotifyKeyCreatedEvent = "New SSH key created"
	NotifyKeyRotatedEvent = "SSH key rotated"
	NotifyKeySecuredEvent = "SSH key secured"
	NotifyKeyAddedEvent   = "SSH key added to agent"
	NotifyKeyRemovedEvent = "SSH key removed from agent"

	// Warning notifications
	NotifyKeyUnprotectedEvent = "SSH key not protected"
	NotifyKeyExpiringEvent    = "SSH key rotation needed"
	NotifyAgentIssueEvent     = "SSH agent issue"

	// Security alerts
	NotifySecurityIssueEvent = "Security issue detected"
	NotifySuspiciousUseEvent = "Suspicious key usage"
)

type Notification struct {
	Title    string
	Message  string
	Type     NotificationType
	Duration time.Duration
}

// Helper functions for notifications
func NotifyRotationNeeded(daysUntilRotation int) {
	SendNotification(Notification{
		Title:    NotifyKeyExpiringEvent,
		Message:  fmt.Sprintf("SSH key rotation recommended in %d days", daysUntilRotation),
		Type:     NotifyWarning,
		Duration: 10 * time.Second,
	})
}

func NotifyAgentStatus(keyPath string, added bool) {
	var title, message string
	if added {
		title = NotifyKeyAddedEvent
		message = fmt.Sprintf("SSH key added to agent: %s", keyPath)
	} else {
		title = NotifyKeyRemovedEvent
		message = fmt.Sprintf("SSH key removed from agent: %s", keyPath)
	}

	SendNotification(Notification{
		Title:    title,
		Message:  message,
		Type:     NotifyInfo,
		Duration: 5 * time.Second,
	})
}

func SendNotification(n Notification) error {
	// Always print to console
	printNotification(n)

	// Try native notifications if available
	switch runtime.GOOS {
	case "darwin":
		return sendDarwinNotification(n)
	case "windows":
		return sendWindowsNotification(n)
	}
	return nil
}

func printNotification(n Notification) {
	var prefix string
	switch n.Type {
	case NotifyError:
		prefix = "❌ ERROR"
	case NotifyWarning:
		prefix = "⚠️  WARNING"
	case NotifySuccess:
		prefix = "✅ SUCCESS"
	default:
		prefix = "ℹ️  INFO"
	}

	fmt.Printf("\n%s: %s\n%s\n", prefix, n.Title, n.Message)
}

func sendDarwinNotification(n Notification) error {
	// Use terminal-notifier if available (more reliable than osascript)
	if _, err := exec.LookPath("terminal-notifier"); err == nil {
		cmd := exec.Command("terminal-notifier",
			"-title", "Keyman",
			"-subtitle", n.Title,
			"-message", n.Message,
			"-sound", "default")
		return cmd.Run()
	}

	// Fallback to osascript
	script := fmt.Sprintf(`display notification "%s" with title "Keyman" subtitle "%s"`,
		n.Message, n.Title)
	cmd := exec.Command("osascript", "-e", script)
	return cmd.Run()
}

func sendWindowsNotification(n Notification) error {
	// Use msg.exe for Windows (more reliable than PowerShell)
	cmd := exec.Command("msg", "*",
		fmt.Sprintf("Keyman - %s\n%s", n.Title, n.Message))

	// If msg.exe fails, try PowerShell as fallback
	if err := cmd.Run(); err != nil {
		script := fmt.Sprintf(`
			Add-Type -AssemblyName System.Windows.Forms
			$notify = New-Object System.Windows.Forms.NotifyIcon
			$notify.Icon = [System.Drawing.SystemIcons]::Information
			$notify.BalloonTipIcon = "Info"
			$notify.BalloonTipTitle = "Keyman - %s"
			$notify.BalloonTipText = "%s"
			$notify.Visible = $True
			$notify.ShowBalloonTip(5000)
		`, n.Title, n.Message)

		cmd = exec.Command("powershell", "-Command", script)
		return cmd.Run()
	}
	return nil
}

// Function to track key usage
func TrackKeyUsage(keyPath string, action string) error {
	homeDir, _ := os.UserHomeDir()
	auditDir := filepath.Join(homeDir, ".config", "keyman", "audit")
	os.MkdirAll(auditDir, 0700)

	auditFile := filepath.Join(auditDir, "usage.log")
	entry := fmt.Sprintf("[%s] %s: %s\n", time.Now().Format(time.RFC3339), action, keyPath)

	// Append to audit log
	f, err := os.OpenFile(auditFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()

	if _, err := f.WriteString(entry); err != nil {
		return err
	}

	// Check for suspicious activity
	if err := checkForSuspiciousActivity(auditFile); err != nil {
		SendNotification(Notification{
			Title:   "Security Alert",
			Message: fmt.Sprintf("Suspicious SSH key activity detected: %v", err),
			Type:    "warning",
		})
	}

	return nil
}

func checkForSuspiciousActivity(auditFile string) error {
	// Read last 100 entries
	content, err := os.ReadFile(auditFile)
	if err != nil {
		return nil // Ignore if file doesn't exist yet
	}

	lines := strings.Split(string(content), "\n")
	if len(lines) < 2 {
		return nil
	}

	// Check for rapid successive uses
	var recentUses []time.Time
	for i := len(lines) - 2; i >= 0 && i >= len(lines)-100; i-- {
		if strings.TrimSpace(lines[i]) == "" {
			continue
		}

		timeStr := strings.Split(strings.Trim(lines[i], "[]"), "]")[0]
		t, err := time.Parse(time.RFC3339, timeStr)
		if err != nil {
			continue
		}
		recentUses = append(recentUses, t)
	}

	// Alert if more than 10 uses in 1 minute
	if len(recentUses) >= 10 {
		duration := recentUses[0].Sub(recentUses[9])
		if duration < time.Minute {
			return fmt.Errorf("high frequency key usage detected: %d uses in %v", 10, duration)
		}
	}

	return nil
}
