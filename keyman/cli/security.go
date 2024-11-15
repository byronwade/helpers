package cli

import (
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type KeyInfo struct {
	Path           string
	Type           string // "rsa", "ed25519", etc.
	Bits           int    // For RSA keys
	IsEncrypted    bool
	Comment        string
	CreatedAt      time.Time
	LastUsed       time.Time
	PasswordStatus string // "protected" or "unprotected"
}

type SecurityScanner struct {
	LastScan time.Time
	Findings []SecurityFinding
}

func NewSecurityScanner() *SecurityScanner {
	return &SecurityScanner{
		LastScan: time.Now(),
		Findings: make([]SecurityFinding, 0),
	}
}

func (s *SecurityScanner) RunScan() []SecurityFinding {
	s.Findings = make([]SecurityFinding, 0)

	homeDir, _ := os.UserHomeDir()
	sshDir := filepath.Join(homeDir, ".ssh")

	s.checkDirectoryPermissions(sshDir)
	s.findUnauthorizedKeys(sshDir)
	s.checkKeyEncryption(sshDir)
	s.checkKeyPermissions(sshDir)
	s.checkKeyStrength(sshDir)
	s.checkSSHAgent()

	s.LastScan = time.Now()
	return s.Findings
}

func (s *SecurityScanner) checkDirectoryPermissions(sshDir string) {
	info, err := os.Stat(sshDir)
	if err != nil {
		s.Findings = append(s.Findings, SecurityFinding{
			Type:        "permission",
			Description: "SSH directory not found",
			Path:        sshDir,
			Severity:    "high",
		})
		return
	}

	mode := info.Mode().Perm()
	if runtime.GOOS != "windows" && mode != 0700 {
		s.Findings = append(s.Findings, SecurityFinding{
			Type:        "permission",
			Description: fmt.Sprintf("SSH directory has incorrect permissions: %o (should be 700)", mode),
			Path:        sshDir,
			Severity:    "high",
		})
	}
}

func (s *SecurityScanner) findUnauthorizedKeys(sshDir string) {
	files, err := ioutil.ReadDir(sshDir)
	if err != nil {
		return
	}

	var privateKeys []string
	for _, file := range files {
		if strings.Contains(file.Name(), "id_") && !strings.HasSuffix(file.Name(), ".pub") {
			privateKeys = append(privateKeys, file.Name())
		}
	}

	if len(privateKeys) > 1 {
		s.Findings = append(s.Findings, SecurityFinding{
			Type:        "multiple_keys",
			Description: fmt.Sprintf("Found %d private keys. Best practice is to maintain only one.", len(privateKeys)),
			Path:        sshDir,
			Severity:    "medium",
		})
	}
}

func (s *SecurityScanner) checkKeyEncryption(sshDir string) {
	files, err := ioutil.ReadDir(sshDir)
	if err != nil {
		return
	}

	for _, file := range files {
		if strings.Contains(file.Name(), "id_") && !strings.HasSuffix(file.Name(), ".pub") {
			keyPath := filepath.Join(sshDir, file.Name())
			if !isKeyEncrypted(keyPath) {
				s.Findings = append(s.Findings, SecurityFinding{
					Type:        "unencrypted",
					Description: "Private key is not password protected",
					Path:        keyPath,
					Severity:    "high",
				})
			}
		}
	}
}

func (s *SecurityScanner) checkKeyPermissions(sshDir string) {
	files, err := ioutil.ReadDir(sshDir)
	if err != nil {
		return
	}

	for _, file := range files {
		if strings.Contains(file.Name(), "id_") && !strings.HasSuffix(file.Name(), ".pub") {
			keyPath := filepath.Join(sshDir, file.Name())
			info, err := os.Stat(keyPath)
			if err != nil {
				continue
			}

			mode := info.Mode().Perm()
			if runtime.GOOS != "windows" && mode != 0600 {
				s.Findings = append(s.Findings, SecurityFinding{
					Type:        "permission",
					Description: fmt.Sprintf("Private key has incorrect permissions: %o (should be 600)", mode),
					Path:        keyPath,
					Severity:    "high",
				})
			}
		}
	}
}

func isKeyEncrypted(keyPath string) bool {
	cmd := exec.Command("ssh-keygen", "-y", "-f", keyPath, "-P", "")
	err := cmd.Run()
	return err != nil
}

func (s *SecurityScanner) GetKeyInfo(keyPath string) (*KeyInfo, error) {
	info := &KeyInfo{
		Path: keyPath,
	}

	// Check if key exists
	if _, err := os.Stat(keyPath); err != nil {
		return nil, fmt.Errorf("key not found: %v", err)
	}

	// Check if key is encrypted
	cmd := exec.Command("ssh-keygen", "-y", "-f", keyPath, "-P", "")
	if err := cmd.Run(); err != nil {
		// Key requires password = encrypted
		info.IsEncrypted = true
		info.PasswordStatus = "protected"
	} else {
		info.IsEncrypted = false
		info.PasswordStatus = "unprotected"
	}

	// Get key type and bits
	cmd = exec.Command("ssh-keygen", "-lf", keyPath)
	output, err := cmd.Output()
	if err == nil {
		parts := strings.Fields(string(output))
		if len(parts) >= 2 {
			info.Bits = parseInt(parts[0])
			info.Type = strings.ToLower(strings.TrimPrefix(parts[1], "("))
			info.Type = strings.TrimSuffix(info.Type, ")")
		}
	}

	// Get creation time
	fileInfo, err := os.Stat(keyPath)
	if err == nil {
		info.CreatedAt = fileInfo.ModTime()
	}

	return info, nil
}

func (s *SecurityScanner) checkKeyStrength(sshDir string) {
	files, err := ioutil.ReadDir(sshDir)
	if err != nil {
		return
	}

	for _, file := range files {
		if strings.Contains(file.Name(), "id_") && !strings.HasSuffix(file.Name(), ".pub") {
			keyPath := filepath.Join(sshDir, file.Name())
			keyInfo, err := s.GetKeyInfo(keyPath)
			if err != nil {
				continue
			}

			// Check key strength
			if keyInfo.Type == "rsa" && keyInfo.Bits < 4096 {
				s.Findings = append(s.Findings, SecurityFinding{
					Type:        "weak_key",
					Description: fmt.Sprintf("RSA key with %d bits (recommended: 4096 bits)", keyInfo.Bits),
					Path:        keyPath,
					Severity:    "medium",
				})
			}
		}
	}
}

func (s *SecurityScanner) checkSSHAgent() error {
	if runtime.GOOS == "windows" {
		return s.checkWindowsSSHAgent()
	}
	return s.checkUnixSSHAgent()
}

func (s *SecurityScanner) checkWindowsSSHAgent() error {
	cmd := exec.Command("powershell", "-Command", "Get-Service ssh-agent")
	output, err := cmd.Output()

	if err != nil || !strings.Contains(string(output), "Running") {
		s.Findings = append(s.Findings, SecurityFinding{
			Type:        "ssh_agent",
			Description: "SSH agent is not running. This means you'll need to enter your password more frequently.",
			Severity:    "medium",
		})
	}
	return nil
}

func (s *SecurityScanner) checkUnixSSHAgent() error {
	if os.Getenv("SSH_AUTH_SOCK") == "" {
		s.Findings = append(s.Findings, SecurityFinding{
			Type:        "ssh_agent",
			Description: "SSH agent is not running. This means you'll need to enter your password more frequently.",
			Severity:    "medium",
		})
	}
	return nil
}

func (s *SecurityScanner) ensureSSHAgentRunning() error {
	if runtime.GOOS == "windows" {
		cmd := exec.Command("powershell", "-Command", `
			$service = Get-Service ssh-agent
			if ($service.Status -ne 'Running') {
				Set-Service -Name ssh-agent -StartupType Automatic
				Start-Service ssh-agent
			}
	 `)
		return cmd.Run()
	} else {
		if os.Getenv("SSH_AUTH_SOCK") == "" {
			cmd := exec.Command("eval", "$(ssh-agent -s)")
			return cmd.Run()
		}
	}
	return nil
}

// Helper function to parse integers
func parseInt(s string) int {
	var result int
	fmt.Sscanf(s, "%d", &result)
	return result
}
