package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type model struct {
	activeTab int
	tabs      []string
	outputs   []string
	processes []*exec.Cmd
	ready     bool
	viewport  viewport.Model
	mu        sync.Mutex
}

func initialModel() model {
	return model{
		tabs:    []string{"npm run dev", "npm run build"},
		outputs: make([]string, 2),
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			// Clean up processes before exiting
			for _, p := range m.processes {
				if p != nil && p.Process != nil {
					p.Process.Kill()
				}
			}
			return m, tea.Quit
		case "tab":
			m.activeTab = (m.activeTab + 1) % len(m.tabs)
		case "shift+tab":
			m.activeTab = (m.activeTab - 1 + len(m.tabs)) % len(m.tabs)
		}

	case tea.WindowSizeMsg:
		if !m.ready {
			m.viewport = viewport.New(msg.Width, msg.Height-4)
			m.ready = true
		} else {
			m.viewport.Width = msg.Width
			m.viewport.Height = msg.Height - 4
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

func (m model) View() string {
	if !m.ready {
		return "\n  Initializing..."
	}

	// Render tabs
	var tabs []string
	for i, tab := range m.tabs {
		style := lipgloss.NewStyle().Padding(0, 1)
		if i == m.activeTab {
			style = style.Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230"))
		} else {
			style = style.Background(lipgloss.Color("236")).Foreground(lipgloss.Color("242"))
		}
		tabs = append(tabs, style.Render(tab))
	}
	tabRow := lipgloss.JoinHorizontal(lipgloss.Top, tabs...)

	// Render content
	m.mu.Lock()
	content := m.outputs[m.activeTab]
	m.mu.Unlock()
	m.viewport.SetContent(content)

	return fmt.Sprintf(
		"%s\n%s\n%s",
		tabRow,
		strings.Repeat("─", m.viewport.Width),
		m.viewport.View(),
	)
}

func captureOutput(cmd *exec.Cmd, outputIndex int, m *model) {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Printf("Error creating stdout pipe: %v\n", err)
		return
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		fmt.Printf("Error creating stderr pipe: %v\n", err)
		return
	}

	if err := cmd.Start(); err != nil {
		fmt.Printf("Error starting process: %v\n", err)
		return
	}

	// Read stdout
	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			m.mu.Lock()
			m.outputs[outputIndex] += line + "\n"
			m.mu.Unlock()
		}
	}()

	// Read stderr
	go func() {
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			line := scanner.Text()
			m.mu.Lock()
			m.outputs[outputIndex] += line + "\n"
			m.mu.Unlock()
		}
	}()
}

func main() {
	m := initialModel()

	// Start the npm processes
	// npm run dev
	devCmd := exec.Command("npm", "run", "dev")
	devCmd.Dir = "../frontend"
	m.processes = append(m.processes, devCmd)
	go captureOutput(devCmd, 0, &m)

	// npm run build
	buildCmd := exec.Command("npm", "run", "build")
	buildCmd.Dir = "../frontend"
	m.processes = append(m.processes, buildCmd)
	go captureOutput(buildCmd, 1, &m)

	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
		os.Exit(1)
	}
}
