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

# Check OS compatibility
if [[ "$OS" != "Linux" && "$OS" != "Darwin" ]]; then
    log_error "Unsupported OS. This script supports Linux and macOS."
fi

# Check Go installation
if ! command -v go &> /dev/null; then
    log_error "Go is not installed. Please install Go and try again."
fi

GO_VERSION=$(go version | awk '{print $3}')
MIN_GO_VERSION="go1.16"

# Function to compare Go versions
version_greater_equal() {
    [ "$(printf '%s\n' "$MIN_GO_VERSION" "$GO_VERSION" | sort -V | head -n1)" = "$MIN_GO_VERSION" ]
}

if ! version_greater_equal; then
    log_error "Go version $MIN_GO_VERSION or higher is required. Installed version is $GO_VERSION."
fi

log_success "Go is installed (version $GO_VERSION)."

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_info "Script directory: $SCRIPT_DIR"

# Ensure the gitdone.go file exists in the script directory
if [ ! -f "$SCRIPT_DIR/gitdone.go" ]; then
    log_error "gitdone.go file not found in the script directory ($SCRIPT_DIR)!"
fi

# Initialize a new Go module if needed
cd "$SCRIPT_DIR" || log_error "Failed to change to script directory."
if [ ! -f "go.mod" ]; then
    log_info "Initializing Go module..."
    go mod init gitdone || log_error "Failed to initialize Go module."
else
    log_info "Go module already initialized."
fi

# Install dependencies
log_info "Ensuring dependencies are up to date..."
go mod tidy || log_error "Failed to tidy Go module."

# Build the Go program
log_info "Building the gitdone binary..."
go build -o gitdone "$SCRIPT_DIR/gitdone.go" || log_error "Failed to build gitdone binary."

# Find a writable directory in PATH
log_info "Searching for a writable directory in PATH..."

IFS=':' read -ra ADDR <<< "$PATH"
INSTALL_DIR=""
for dir in "${ADDR[@]}"; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then
        INSTALL_DIR="$dir"
        break
    fi
done

if [ -z "$INSTALL_DIR" ]; then
    # Create a local bin directory and add it to PATH
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR" || log_error "Failed to create $INSTALL_DIR."
    log_info "No writable directory in PATH found. Created $INSTALL_DIR."

    # Update PATH in current session
    export PATH="$PATH:$INSTALL_DIR"

    # Update PATH in shell profile
    SHELL_PROFILE=""
    if [ -n "$SHELL" ]; then
        case "$SHELL" in
            */bash)
                if [ -f "$HOME/.bash_profile" ]; then
                    SHELL_PROFILE="$HOME/.bash_profile"
                elif [ -f "$HOME/.bashrc" ]; then
                    SHELL_PROFILE="$HOME/.bashrc"
                else
                    SHELL_PROFILE="$HOME/.profile"
                fi
                ;;
            */zsh)
                SHELL_PROFILE="$HOME/.zshrc"
                ;;
            *)
                SHELL_PROFILE="$HOME/.profile"
                ;;
        esac
    else
        SHELL_PROFILE="$HOME/.profile"
    fi
    log_info "Adding $INSTALL_DIR to PATH in $SHELL_PROFILE..."
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_PROFILE"
fi

# Install the binary
log_info "Installing gitdone binary to $INSTALL_DIR..."
mv gitdone "$INSTALL_DIR/" || log_error "Failed to move gitdone binary to $INSTALL_DIR/."

# Verify installation
if command -v gitdone >/dev/null 2>&1; then
    log_success "gitdone successfully installed and ready to use."
else
    log_error "gitdone installation failed!"
fi

log_success "Setup complete. You can now run 'gitdone' from anywhere."
