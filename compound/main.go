package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	data, err := os.ReadFile("compound.json")
	if err != nil {
		fmt.Printf("Failed to read compound.json fail, make sure it exists.\r\n%v\r\n", err)
		os.Exit(1)
	}

	var procConfigs []ProcessCfg
	err = json.Unmarshal(data, &procConfigs)
	if err != nil {
		fmt.Printf("Failed to parse proceses in compound.json. Check the format is correct.\r\n%v\r\n", err)
		os.Exit(1)
	}

	var processes []Process
	for i, pc := range procConfigs {
		cmd := exec.Command(pc.Process.Command, pc.Process.Args...)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if pc.Process.Cwd != "" {
			cmd.Dir = pc.Process.Cwd
		}
		process := Process{
			pc.Name,
			make(chan string),
			cmd,
			i,
		}
		processes = append(processes, process)
		go captureOutput(&process)
	}

	// Extra cleanup should something fail so processes aren't dangling
	defer cleanupProcesses(processes)

	m := InitialModel(processes)

	prog := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := prog.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
		os.Exit(1)
	}
}
