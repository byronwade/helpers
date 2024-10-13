#!/bin/bash

# Detect OS
OS="$(uname -s)"

# Install Go
if ! [ -x "$(command -v go)" ]; then
  echo "Go is not installed. Installing Go..."
  
  if [[ "$OS" == "Linux" ]]; then
    curl -OL https://golang.org/dl/go1.18.4.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.18.4.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    source ~/.bashrc
  elif [[ "$OS" == "Darwin" ]]; then
    # macOS installation via Homebrew
    if ! [ -x "$(command -v brew)" ]; then
      echo "Homebrew not found. Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew install go
  fi
else
  echo "Go is already installed."
fi

# Remove any old gitdone setup
if [ -f "/usr/local/bin/gitdone" ]; then
  echo "Removing old gitdone binary..."
  sudo rm /usr/local/bin/gitdone
fi

# Create the project directory if it doesn't exist
mkdir -p ~/gitdone
cd ~/gitdone

# Initialize a new Go module for the project
if [ -f "go.mod" ]; then
  echo "Removing old go.mod and go.sum files..."
  rm go.mod go.sum 2>/dev/null
fi

go mod init gitdone

# Ensure the gitdone.go file exists in the current directory
if [ ! -f "$OLDPWD/gitdone.go" ]; then
  echo "Error: gitdone.go file not found in the current directory!"
  exit 1
fi

# Build the Go program
echo "Building the gitdone binary..."
go build -o gitdone "$OLDPWD/gitdone.go"

# Move the binary to a directory in your PATH
if [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]; then
  sudo mv gitdone /usr/local/bin/
  echo "gitdone installed at /usr/local/bin/"
fi

# Verify installation
if command -v gitdone >/dev/null 2>&1; then
  echo "gitdone successfully installed and ready to use."
else
  echo "Error: gitdone installation failed!"
fi

# Provide feedback
echo "Setup complete. You can now run 'gitdone' from anywhere."
