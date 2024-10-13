#!/bin/bash

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${YELLOW}INFO: $1${NC}"; }
log_success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
log_error() { echo -e "${RED}ERROR: $1${NC}"; exit 1; }

# Detect OS
OS="$(uname -s)"
log_info "Detected OS: $OS"

# Check Go installation
if ! command -v go &> /dev/null; then
    log_error "Go is not installed. Please install Go and try again."
fi

log_success "Go is installed."

# Remove any old gitdone setup
if [ -f "/usr/local/bin/gitdone" ]; then
    log_info "Removing old gitdone binary..."
    sudo rm /usr/local/bin/gitdone || log_error "Failed to remove old gitdone binary."
fi

# Create the project directory if it doesn't exist
mkdir -p ~/gitdone || log_error "Failed to create ~/gitdone directory."
cd ~/gitdone || log_error "Failed to change to ~/gitdone directory."

# Initialize a new Go module for the project
if [ -f "go.mod" ]; then
    log_info "Removing old go.mod and go.sum files..."
    rm go.mod go.sum 2>/dev/null
fi

go mod init gitdone || log_error "Failed to initialize Go module."

# Install required dependencies
log_info "Installing dependencies..."
go get github.com/fatih/color || log_error "Failed to install github.com/fatih/color."

# Ensure the gitdone.go file exists in the parent directory
if [ ! -f "$OLDPWD/gitdone.go" ]; then
    log_error "gitdone.go file not found in the parent directory!"
fi

# Build the Go program
log_info "Building the gitdone binary..."
go build -o gitdone "$OLDPWD/gitdone.go" || log_error "Failed to build gitdone binary."

# Move the binary to a directory in your PATH
if [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]; then
    sudo mv gitdone /usr/local/bin/ || log_error "Failed to move gitdone binary to /usr/local/bin/."
    log_success "gitdone installed at /usr/local/bin/"
else
    log_error "Unsupported OS for automatic installation. Please manually move the gitdone binary to a directory in your PATH."
fi

# Verify installation
if command -v gitdone >/dev/null 2>&1; then
    log_success "gitdone successfully installed and ready to use."
else
    log_error "gitdone installation failed!"
fi

log_success "Setup complete. You can now run 'gitdone' from anywhere."
