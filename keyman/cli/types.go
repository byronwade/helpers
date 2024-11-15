package cli

// Command represents a CLI command
type Command struct {
	Name        string
	Description string
	Action      func() error
}

// SecurityFinding represents a security issue found during scanning
type SecurityFinding struct {
	Type        string // "permission", "multiple_keys", "unencrypted"
	Description string
	Path        string
	Severity    string // "high", "medium", "low"
}

// NotificationType represents the type of notification
type NotificationType string

// NotificationTypes
const (
	NotifyInfo    NotificationType = "info"
	NotifyWarning NotificationType = "warning"
	NotifyError   NotificationType = "error"
	NotifySuccess NotificationType = "success"
)
