package cli

import (
	"fmt"
)

func Scan() error {
	scanner := NewSecurityScanner()
	findings := scanner.RunScan()

	if len(findings) == 0 {
		fmt.Println("✅ No security issues found")
		return nil
	}

	fmt.Printf("Found %d security issues:\n\n", len(findings))

	for i, finding := range findings {
		fmt.Printf("%d. [%s] %s\n", i+1, finding.Severity, finding.Description)
		fmt.Printf("   Path: %s\n", finding.Path)
		fmt.Printf("   Type: %s\n\n", finding.Type)
	}

	return nil
}
