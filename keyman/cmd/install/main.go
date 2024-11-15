package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func main() {
	// Get the installation directory
	var installDir string
	if runtime.GOOS == "windows" {
		installDir = filepath.Join(os.Getenv("LOCALAPPDATA"), "Keyman")
	} else {
		homeDir, _ := os.UserHomeDir()
		installDir = filepath.Join(homeDir, ".local", "bin")
	}

	// Create installation directory
	os.MkdirAll(installDir, 0755)

	// Build the binary
	fmt.Println("Building Keyman...")

	// Get current directory
	currentDir, err := os.Getwd()
	if err != nil {
		fmt.Printf("Failed to get current directory: %v\n", err)
		os.Exit(1)
	}

	// Build command with proper path
	buildCmd := exec.Command("go", "build", "-o", filepath.Join(installDir, "keyman"))
	buildCmd.Stdout = os.Stdout
	buildCmd.Stderr = os.Stderr
	buildCmd.Dir = currentDir // Set working directory

	if err := buildCmd.Run(); err != nil {
		fmt.Printf("Build failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Keyman installed to: %s\n", installDir)

	// Add to PATH if needed
	if runtime.GOOS == "windows" {
		userPath := os.Getenv("PATH")
		if !pathContains(userPath, installDir) {
			fmt.Println("Adding to PATH...")
			cmd := exec.Command("powershell", "-Command",
				"[Environment]::SetEnvironmentVariable('Path', "+
					"[Environment]::GetEnvironmentVariable('Path', 'User') + ';' + '"+
					installDir+"', 'User')")
			cmd.Run()

			// Update current session PATH
			os.Setenv("PATH", os.Getenv("PATH")+";"+installDir)
		}

		// Run initial setup using the newly installed binary
		fmt.Println("\nRunning initial SSH key initialization...")
		setupCmd := exec.Command(filepath.Join(installDir, "keyman"), "init")
		setupCmd.Stdout = os.Stdout
		setupCmd.Stderr = os.Stderr
		setupCmd.Stdin = os.Stdin
		setupCmd.Run()

		fmt.Println("\nInstallation successful!")
		fmt.Println("Please open a new terminal window and run: keyman init")

		// Don't run setup immediately as PATH isn't updated in current session
		os.Exit(0)
	}
}

func pathContains(path, dir string) bool {
	paths := filepath.SplitList(path)
	for _, p := range paths {
		if strings.EqualFold(p, dir) {
			return true
		}
	}
	return false
}
