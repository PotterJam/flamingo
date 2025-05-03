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

// Represents a single process running in the background
type Process struct {
	// The channel where reader goroutine will pass read output
	buf chan string
	// The cmd that is running, so cleanup can be performed
	cmd *exec.Cmd
	// Index of the running process
	i int
}

type model struct {
	activeTab int
	tabs      []string
	outputs   []string
	ready     bool
	viewport  viewport.Model
	processes []Process
}

func initialModel(processes []Process) model {
	vp := viewport.New(0, 0)
	vp.Style = lipgloss.NewStyle().
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("62"))
	return model{
		activeTab: 0,
		tabs:      []string{"npm run dev", "npm run build"},
		outputs:   make([]string, 2),
		viewport:  vp,
		processes: processes,
	}
}

type TickMsg time.Time

func doTick() tea.Cmd {
	return tea.Tick(time.Millisecond * 100, func(t time.Time) tea.Msg {
		return TickMsg(t)
	})
}

type ProcessMsg struct {
	buf string
	i   int
}

func checkOutputs(m *model) tea.Cmd {
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
				if p.cmd != nil && p.cmd.Process != nil {
					p.cmd.Process.Kill()
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
		return m, tea.Batch(doTick(), checkOutputs(&m))

	case ProcessMsg:
		m.outputs[msg.i] += msg.buf
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
	p.cmd.Env = append(os.Environ(), "FORCE_COLOR=1")

	if err := p.cmd.Start(); err != nil {
		fmt.Printf("Error starting process: %v\n", err)
		return
	}

	go readStream(stdout, p)
	go readStream(stderr, p)
}

func main() {
	var processes []Process

	devCmd := exec.Command("ping", "-i", "0.5", "google.com")
	p := Process{make(chan string), devCmd, 0}
	processes = append(processes, p)
	go captureOutput(&p)

	devCmd2 := exec.Command("ping", "-i", "0.5", "bing.com")
	p2 := Process{make(chan string), devCmd2, 1}
	processes = append(processes, p2)
	go captureOutput(&p2)

	m := initialModel(processes)

	prog := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := prog.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
		os.Exit(1)
	}
}
