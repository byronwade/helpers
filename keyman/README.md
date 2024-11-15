# Keyman: Advanced SSH Key Manager

A secure, cross-platform tool for managing SSH keys with enforced security best practices, automated monitoring, and comprehensive key lifecycle management.

## What is Keyman?

Keyman is a robust SSH key management tool designed to:
- Enforce SSH key security best practices
- Automate key lifecycle management
- Monitor key usage and detect suspicious activity
- Provide native system notifications for security events
- Manage SSH agent integration
- Handle key rotation with configurable schedules

## Core Features

### Security Enforcement
- 🔒 Enforced password protection for private keys
- 🔑 4096-bit RSA or ED25519 key generation
- 🛡️ Proper file permissions enforcement
- 🔐 SSH agent security management
- 🕵️ Continuous security monitoring

### Key Management
- 🔄 Optional automatic key rotation
- 📦 Secure key backup and recovery
- 🏷️ Key comment and metadata management
- 🔍 Key verification and validation
- 🔀 Key format conversion (RSA, ED25519, ECDSA)

### Monitoring & Auditing
- 📊 Real-time security scanning
- 📝 Detailed usage logging
- 🚨 Native system notifications
- 🔍 Suspicious activity detection
- 📈 Usage pattern analysis

## Quick Start

### Windows
```powershell
./install.ps1
```

### macOS/Linux
```bash
chmod +x install.sh
./install.sh
```

## Command Reference

### Essential Commands
```bash
# Initial Setup
keyman init              # First-time setup with guided configuration

# Status & Information
keyman status           # Check key security status and rotation info
keyman view            # Display your public key (safe to share)
keyman audit           # Run comprehensive security audit
```

### Key Management
```bash
# Key Operations
keyman key encrypt     # Add password protection
keyman key password    # Change key password
keyman key comment     # Update key comment
keyman key convert     # Convert between key types
keyman key fingerprint # Show key fingerprint
keyman key verify      # Verify key pair integrity

# Key Rotation
keyman rotation status   # Show rotation settings
keyman rotation enable   # Enable automatic rotation
keyman rotation disable  # Disable automatic rotation
keyman rotation interval # Set rotation interval
keyman rotate           # Manually rotate key
```

### Security Management
```bash
# Security Scanner
keyman scanner status   # Check scanner status
keyman scanner start    # Start security monitoring
keyman scanner stop     # Stop security monitoring
keyman scanner interval # Set scan interval (minutes)

# Security Operations
keyman reset           # Remove all keys and create new ones
```

### SSH Agent Integration
```bash
# Agent Management
keyman agent status    # Check agent status
keyman agent start     # Start SSH agent
keyman agent add       # Add key to agent (cache password)
keyman agent remove    # Remove key from agent
keyman agent clear     # Remove all keys from agent
```

## Key Rotation

### Configuration
```bash
# Enable rotation with 90-day interval
keyman rotation enable
keyman rotation interval 90

# Disable rotation
keyman rotation disable
```

### Rotation Features
- Optional automatic rotation
- Configurable rotation intervals
- Automatic backup of old keys
- Service update notifications
- Rotation status tracking

### Best Practices
1. Enable rotation for production keys
2. Use 90-day rotation for standard security
3. Use 30-day rotation for high security
4. Keep rotation disabled for personal keys

## Security Features

### Key Protection
- Mandatory password protection
- Strong encryption standards
- Secure file permissions
- Key usage monitoring

### Activity Monitoring
- Real-time security scanning
- Suspicious activity detection
- Usage pattern analysis
- Automated notifications

### SSH Agent Security
- Secure key caching
- Session isolation
- Automatic timeouts
- Access control

## System Notifications

Keyman provides native notifications for:
- Security issues detected
- Key rotation reminders
- Suspicious activity alerts
- SSH agent status changes
- Key operations (creation, rotation)

## Troubleshooting

### Common Issues
```bash
# Check key status
keyman status

# Run security audit
keyman audit

# Verify key integrity
keyman key verify

# Reset SSH agent
keyman agent clear
keyman agent start
```

## Development

### Project Structure
```
keyman/
├── cli/
│   ├── commands.go      # Command implementations
│   ├── security.go      # Security checks
│   ├── notifications.go # System notifications
│   ├── types.go        # Type definitions
│   └── scanner.go      # Security scanner
├── main.go             # Main entry point
└── install.ps1/sh      # Installation scripts
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Submit pull request

## License

MIT License - See LICENSE file for details
