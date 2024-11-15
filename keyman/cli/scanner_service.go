package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type ScannerService struct {
	interval   time.Duration
	stopChan   chan struct{}
	isRunning  bool
	mutex      sync.Mutex
	lastScanAt time.Time
	configPath string
}

var (
	scannerInstance *ScannerService
	once            sync.Once
)

func GetScannerService() *ScannerService {
	once.Do(func() {
		homeDir, _ := os.UserHomeDir()
		configPath := filepath.Join(homeDir, ".config", "keyman", "scanner.conf")

		scannerInstance = &ScannerService{
			interval:   15 * time.Minute, // Default scan interval
			stopChan:   make(chan struct{}),
			configPath: configPath,
		}

		// Load custom interval if configured
		if content, err := os.ReadFile(configPath); err == nil {
			var minutes int
			if _, err := fmt.Sscanf(string(content), "interval=%d", &minutes); err == nil {
				scannerInstance.interval = time.Duration(minutes) * time.Minute
			}
		}
	})
	return scannerInstance
}

func (s *ScannerService) Start() error {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	if s.isRunning {
		return nil
	}

	s.isRunning = true
	go s.run()

	// Save scanner status
	os.MkdirAll(filepath.Dir(s.configPath), 0700)
	return os.WriteFile(s.configPath+".status", []byte("running"), 0600)
}

func (s *ScannerService) Stop() {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	if !s.isRunning {
		return
	}

	s.stopChan <- struct{}{}
	s.isRunning = false
	os.WriteFile(s.configPath+".status", []byte("stopped"), 0600)
}

func (s *ScannerService) run() {
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	// Run initial scan
	s.performScan()

	for {
		select {
		case <-ticker.C:
			s.performScan()
		case <-s.stopChan:
			return
		}
	}
}

func (s *ScannerService) performScan() {
	scanner := NewSecurityScanner()
	findings := scanner.RunScan()

	// Check for suspicious findings
	for _, finding := range findings {
		if isSuspiciousFinding(finding) {
			SendNotification(Notification{
				Title:    "Security Alert",
				Message:  fmt.Sprintf("Suspicious SSH key activity detected: %s", finding.Description),
				Type:     NotifyWarning,
				Duration: 0, // Notification stays until dismissed
			})

			// Log the suspicious activity
			TrackKeyUsage(finding.Path, "suspicious_activity_detected")
		}
	}

	s.lastScanAt = time.Now()
}

func isSuspiciousFinding(finding SecurityFinding) bool {
	// Define what constitutes suspicious activity
	switch finding.Type {
	case "unencrypted":
		return true // Unencrypted keys are always suspicious
	case "permission":
		return finding.Severity == "high" // Incorrect permissions are suspicious
	case "multiple_keys":
		return true // Multiple keys might indicate unauthorized additions
	case "weak_key":
		return finding.Severity == "high" // Weak keys are suspicious
	default:
		return false
	}
}

// Add to main.go to start the scanner service
func init() {
	scanner := GetScannerService()
	if err := scanner.Start(); err != nil {
		fmt.Printf("Warning: Failed to start security scanner: %v\n", err)
	}
}
