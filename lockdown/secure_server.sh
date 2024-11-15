#!/bin/bash

# Enhanced Server Security Script
# Usage: sudo bash secure_server.sh
# Author: Your Name
# Version: 1.0

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[+]${NC} $1"
}

error() {
    echo -e "${RED}[!]${NC} $1"
}

# Function to create a new admin user with enhanced security
create_admin_user() {
    log "Creating new admin user..."
    read -p "Enter the new admin username: " username
    
    # Create user with secure defaults
    useradd -m -s /bin/bash "$username"
    usermod -aG sudo "$username"

    # Set up SSH authentication
    mkdir -p "/home/$username/.ssh"
    read -p "Paste the public SSH key (leave empty for password auth): " ssh_key
    
    if [ ! -z "$ssh_key" ]; then
        echo "$ssh_key" > "/home/$username/.ssh/authorized_keys"
        chmod 600 "/home/$username/.ssh/authorized_keys"
        chmod 700 "/home/$username/.ssh"
        chown -R "$username:$username" "/home/$username/.ssh"
        log "SSH key authentication configured"
        
        # Disable password authentication
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    else
        log "Setting up password authentication..."
        passwd "$username"
    fi
}

# Enhanced firewall setup
setup_firewall() {
    log "Configuring UFW firewall..."
    apt-get install -y ufw

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow essential services
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Rate limiting for SSH
    ufw limit ssh/tcp

    # Enable firewall
    echo "y" | ufw enable
    ufw status verbose
}

# Enhanced security tools installation
install_security_tools() {
    log "Installing and configuring security tools..."
    
    # Update package list
    apt-get update

    # Install essential security packages
    apt-get install -y \
        fail2ban \
        clamav \
        clamav-daemon \
        rkhunter \
        chkrootkit \
        unattended-upgrades \
        apt-listchanges \
        needrestart \
        auditd \
        aide \
        logwatch \
        lynis \
        mtr \
        htop \
        ncdu \
        tree \
        tmux

    # Configure fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    systemctl enable fail2ban
    systemctl start fail2ban

    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Enable automatic updates
    echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
}

# Enhanced SSH hardening
harden_ssh() {
    log "Hardening SSH configuration..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Configure SSH
    cat > /etc/ssh/sshd_config << EOF
Port 22
Protocol 2
PermitRootLogin no
MaxAuthTries 3
PubkeyAuthentication yes
PermitEmptyPasswords no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $username
EOF

    systemctl restart sshd
}

# System hardening
harden_system() {
    log "Applying system hardening..."

    # Configure system-wide security settings
    cat >> /etc/sysctl.conf << EOF
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

    sysctl -p
}

# Configure secure password policies
setup_password_policies() {
    log "Configuring password policies..."
    
    apt-get install -y libpam-pwquality
    
    # Configure password quality requirements
    cat > /etc/security/pwquality.conf << EOF
minlen = 12
minclass = 4
maxrepeat = 2
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforcing = 1
EOF

    # Configure password aging policies
    sed -i 's/PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
    sed -i 's/PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' /etc/login.defs
    sed -i 's/PASS_WARN_AGE.*/PASS_WARN_AGE 14/' /etc/login.defs
}

# Setup security auditing
setup_audit_system() {
    log "Configuring system auditing..."
    
    # Configure auditd
    cat > /etc/audit/rules.d/audit.rules << EOF
# Log file changes
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity

# Log command execution
-a exit,always -F arch=b64 -S execve -k exec
-a exit,always -F arch=b32 -S execve -k exec

# Log system calls
-a exit,always -F arch=b64 -S mount -k mount
-a exit,always -F arch=b64 -S unlink -S rmdir -S rename -k delete
EOF

    systemctl enable auditd
    systemctl restart auditd
}

# Setup automated security reporting
setup_security_reporting() {
    log "Configuring security reporting..."
    
    # Configure logwatch for daily reports
    cat > /etc/logwatch/conf/logwatch.conf << EOF
Output = mail
Format = html
MailTo = root
MailFrom = logwatch@$(hostname)
Detail = High
Service = All
Range = yesterday
EOF

    # Setup AIDE reporting
    echo "0 3 * * * root /usr/bin/aide --check | mail -s 'AIDE Check Report' root" >> /etc/crontab
    
    # Setup Lynis automated audits
    echo "0 4 * * * root /usr/sbin/lynis audit system --cronjob > /var/log/lynis-audit.log" >> /etc/crontab
}

# Setup malware scanning
setup_malware_scanning() {
    log "Configuring malware scanning..."
    
    # Configure ClamAV
    systemctl stop clamav-freshclam
    freshclam
    systemctl start clamav-freshclam
    
    # Create weekly scan script
    cat > /etc/cron.weekly/virus-scan << EOF
#!/bin/bash
clamscan -r / --exclude-dir=/sys/ --exclude-dir=/proc/ --exclude-dir=/dev/ -i | mail -s 'ClamAV Scan Report' root
EOF
    chmod +x /etc/cron.weekly/virus-scan
    
    # Configure rkhunter
    rkhunter --update
    rkhunter --propupd
    echo "0 2 * * * root /usr/bin/rkhunter --check --skip-keypress --report-warnings-only | mail -s 'RKHunter Check Report' root" >> /etc/crontab
}

# Main execution
main() {
    log "Starting server security hardening..."
    
    create_admin_user
    setup_firewall
    install_security_tools
    harden_ssh
    harden_system
    setup_password_policies
    setup_audit_system
    setup_security_reporting
    setup_malware_scanning
    
    log "Security hardening completed. Please review the logs and test all services."
    log "It's recommended to reboot the system now."
}

# Run main function
main 