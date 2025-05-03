package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

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
	process   chan string
}

func initialModel() model {
	vp := viewport.New(0, 0)
	vp.Style = lipgloss.NewStyle().
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("62"))
	return model{
		activeTab: 0,
		tabs:      []string{"npm run dev", "npm run build"},
		outputs:   make([]string, 2),
		viewport:  vp,
		process:   make(chan string),
	}
}

type TickMsg time.Time

func doTick() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return TickMsg(t)
	})
}

type ProcessMsg struct {
	buf string
}

func checkOutput(m *model) tea.Cmd {
	select {
	case buf := <-m.process:
		return func() tea.Msg { return ProcessMsg{buf} }
	default:
		return func() tea.Msg { return ProcessMsg{""} }
	}
}

func (m model) Init() tea.Cmd {
	return doTick()
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
			m.viewport.Width = msg.Width
			m.viewport.Height = msg.Height - 4
			m.ready = true
		} else {
			m.viewport.Width = msg.Width
			m.viewport.Height = msg.Height - 4
		}

	case TickMsg:
		return m, tea.Batch(doTick(), checkOutput(&m))

	case ProcessMsg:
		m.outputs[0] += msg.buf
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

func (m model) View() string {
	if !m.ready {
		return "\n  Initializing..."
	}

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

	content := m.outputs[m.activeTab]
	m.viewport.SetContent(content)

	return fmt.Sprintf(
		"%s\n%s\n%s",
		tabRow,
		strings.Repeat("─", m.viewport.Width),
		m.viewport.View(),
	)
}

func readStream(reader io.ReadCloser, outputIndex int, m *model) {
	buf := make([]byte, 1024)
	for {
		n, err := reader.Read(buf)
		if n > 0 {
			m.process <- string(buf[:n])
			// m.outputs[outputIndex] += string(buf[:n])
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

	// Processes spawned won't use terminal colour, so force them do so
	cmd.Env = append(os.Environ(), "FORCE_COLOR=1")

	if err := cmd.Start(); err != nil {
		fmt.Printf("Error starting process: %v\n", err)
		return
	}

	// Read stdout and stderr
	go readStream(stdout, outputIndex, m)
	go readStream(stderr, outputIndex, m)
}

func main() {
	m := initialModel()

	devCmd := exec.Command("ping", "-i", "0.5", "google.com")
	m.processes = append(m.processes, devCmd)
	go captureOutput(devCmd, 0, &m)

	// buildCmd := exec.Command("ping", "-i", "0.5", "bing.com")
	// m.processes = append(m.processes, buildCmd)
	// go captureOutput(buildCmd, 1, &m)

	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
		os.Exit(1)
	}
}
