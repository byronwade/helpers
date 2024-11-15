package main

import (
	"fmt"
	"keyman/cli"
	"os"
	"path/filepath"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		return
	}

	commands := cli.GetCommands()
	command := os.Args[1]

	if cmd, exists := commands[command]; exists {
		if err := cmd.Action(); err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Printf("Unknown command: %s\n", command)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Printf("Usage: %s <command>\n\n", filepath.Base(os.Args[0]))
	fmt.Println("Available commands:")

	commands := cli.GetCommands()
	for name, cmd := range commands {
		fmt.Printf("  %-10s %s\n", name, cmd.Description)
	}
}
