package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
)

type ProcessCfg struct {
	Name    string     `json:"name"`
	Process CommandCfg `json:"process"`
}

type CommandCfg struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
	Cwd     string   `json:"cwd"`
}

// Represents a single process running in the background
type Process struct {
	name string
	// The channel where reader goroutine will pass read output
	buf chan string
	// The cmd that is running, so cleanup can be performed
	cmd *exec.Cmd
	// Index of the running process
	i int
}

func checkOutputs(m *Model) tea.Cmd {
	var batch []tea.Cmd
	for _, p := range m.processes {
		select {
		case buf := <-p.buf:
			batch = append(batch, func() tea.Msg { return ProcessMsg{buf, p.i} })
		default:
			batch = append(batch, func() tea.Msg { return ProcessMsg{"", p.i} })
		}
	}

	return tea.Batch(batch...)
}

func readStream(reader io.ReadCloser, p *Process) {
	buf := make([]byte, 1024)
	for {
		n, err := reader.Read(buf)
		if n > 0 {
			p.buf <- string(buf[:n])
		}
		if err != nil {
			if err != io.EOF {
				fmt.Printf("Error reading from stream: %v\n", err)
			}
			break
		}
	}
	reader.Close()
}

func captureOutput(p *Process) {
	stdout, err := p.cmd.StdoutPipe()
	if err != nil {
		fmt.Printf("Error creating stdout pipe: %v\n", err)
		return
	}

	stderr, err := p.cmd.StderrPipe()
	if err != nil {
		fmt.Printf("Error creating stderr pipe: %v\n", err)
		return
	}

	// Processes spawned won't use terminal colour, so force them do so
	p.cmd.Env = append(os.Environ(),
		"FORCE_COLOR=1",
		"CLICOLOR_FORCE=1",
		"CLICOLOR=1",
		"TERM=xterm-256color",
	)

	if err := p.cmd.Start(); err != nil {
		fmt.Printf("Error starting process: %v\n", err)
		return
	}

	go readStream(stdout, p)
	go readStream(stderr, p)
}

func cleanupProcesses(processes []Process) {
	for _, p := range processes {
		if p.cmd != nil && p.cmd.Process != nil {
			if p.cmd.Process.Pid > 0 {
				syscall.Kill(-p.cmd.Process.Pid, syscall.SIGINT)
			}
		}
	}
}
