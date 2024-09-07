package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	// Define the output binary name and the source directory
	output := "mosql"
	sourceDir := "./cmd"

	// Get the absolute path to the current working directory
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Println("Error getting current working directory:", err)
		os.Exit(1)
	}

	// Construct the full path to the output binary
	outputPath := filepath.Join(cwd, output)

	// Prepare the go build command
	cmd := exec.Command("go", "build", "-o", outputPath, sourceDir)

	// Set the working directory to the root of the workspace
	cmd.Dir = cwd

	// Run the command and capture any output or errors
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	fmt.Println("Building the project...")

	// Execute the build command
	err = cmd.Run()
	if err != nil {
		fmt.Println("Build failed:", err)
		os.Exit(1)
	}

	fmt.Println("Build succeeded! Output binary:", outputPath)
}
