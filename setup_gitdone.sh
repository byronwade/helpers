#!/bin/bash

# Variables
HELPER_DIR="$HOME/git_helpers"
SCRIPT_NAME="gitdone"
OLLAMA_API_URL_DEFAULT="http://localhost:11434"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    echo -e "${1}${2}${NC}"
}

# Function to print error and exit
error_exit() {
    print_color "$RED" "ERROR: $1"
    exit 1
}

# Create helper directory
mkdir -p "$HELPER_DIR"

# Copy the gitdone script and make it executable
cp "$SCRIPT_NAME" "$HELPER_DIR/"
chmod +x "$HELPER_DIR/$SCRIPT_NAME"
print_color "$GREEN" "Copied and made executable: $SCRIPT_NAME"

# Install Python if not installed
if ! command -v python3 &>/dev/null; then
    print_color "$YELLOW" "Python3 not found. Installing Python3..."
    # For macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install python3
    # For Linux (Debian/Ubuntu)
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt update
        sudo apt install -y python3 python3-pip
    fi
fi

# Install required Python packages
print_color "$BLUE" "Installing required Python packages..."
pip3 install requests --user

# Set OLLAMA_API_URL environment variable
OLLAMA_API_URL=${OLLAMA_API_URL:-$OLLAMA_API_URL_DEFAULT}

# Detect shell and set environment variable
SHELL_NAME=$(basename "$SHELL")

if [ "$SHELL_NAME" = "zsh" ]; then
    PROFILE_FILE="$HOME/.zshrc"
elif [ "$SHELL_NAME" = "bash" ]; then
    PROFILE_FILE="$HOME/.bashrc"
else
    PROFILE_FILE="$HOME/.profile"
fi

# Add environment variable to profile if not already present
if ! grep -q "export OLLAMA_API_URL=" "$PROFILE_FILE"; then
    echo "export OLLAMA_API_URL=\"$OLLAMA_API_URL\"" >> "$PROFILE_FILE"
    print_color "$GREEN" "Environment variable added to $PROFILE_FILE."
else
    print_color "$YELLOW" "OLLAMA_API_URL already set in $PROFILE_FILE."
fi

# Add helper directory to PATH if not already present
if ! grep -q "export PATH=\"\$PATH:$HELPER_DIR\"" "$PROFILE_FILE"; then
    echo "export PATH=\"\$PATH:$HELPER_DIR\"" >> "$PROFILE_FILE"
    print_color "$GREEN" "Added $HELPER_DIR to PATH in $PROFILE_FILE."
else
    print_color "$YELLOW" "$HELPER_DIR already in PATH."
fi

print_color "$GREEN" "Setup complete! Please restart your terminal or run 'source $PROFILE_FILE'."

ensure_ollama() {
    if ! command -v ollama &>/dev/null; then
        print_color "$YELLOW" "Ollama not found. Installing Ollama..."
        curl https://ollama.ai/install.sh | sh
    fi

    model_name="llama3.1"
    if ! ollama list | grep -q "$model_name"; then
        print_color "$BLUE" "Pulling the latest $model_name model..."
        ollama pull $model_name
    else
        print_color "$GREEN" "$model_name model is already available."
    fi

    print_color "$BLUE" "Starting Ollama service..."
    ollama serve &
}