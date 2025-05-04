package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type ProcessCfg struct {
	Name    string     `json:"name"`
	Process CommandCfg `json:"process"`
}

type CommandCfg struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
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

type keyMap struct {
	StickToBottom key.Binding
	GoToTop       key.Binding
	NextTab       key.Binding
	PrevTab       key.Binding
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.StickToBottom,
		k.GoToTop,
		k.NextTab,
		k.PrevTab,
	}
}

func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.StickToBottom, k.GoToTop},
		{k.NextTab, k.PrevTab},
	}
}

type model struct {
	activeTab int
	tabs      []string
	outputs   []string
	ready     bool
	// If the viewport should be stuck to the bottom tracking new logs
	sticky    bool
	viewport  viewport.Model
	processes []Process
	help      help.Model
	keys      keyMap
}

func initialModel(procs []Process) model {
	vp := viewport.New(0, 0)
	vp.Style = lipgloss.NewStyle().
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("62"))

	tabs := make([]string, len(procs))
	for i, p := range procs {
		tabs[i] = p.name
	}

	keys := keyMap{
		StickToBottom: key.NewBinding(
			key.WithKeys("s"),
			key.WithHelp("s", "stick to bottom"),
		),
		GoToTop: key.NewBinding(
			key.WithKeys("t"),
			key.WithHelp("t", "go to top"),
		),
		NextTab: key.NewBinding(
			key.WithKeys("tab"),
			key.WithHelp("tab", "next tab"),
		),
		PrevTab: key.NewBinding(
			key.WithKeys("shift+tab"),
			key.WithHelp("shift+tab", "prev tab"),
		),
	}

	return model{
		activeTab: 0,
		tabs:      tabs,
		outputs:   make([]string, 2),
		sticky:    true,
		viewport:  vp,
		processes: procs,
		help:      help.New(),
		keys:      keys,
	}
}

type TickMsg time.Time

func doTick() tea.Cmd {
	return tea.Tick(time.Millisecond*100, func(t time.Time) tea.Msg {
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
	var (
		cmd  tea.Cmd
		cmds []tea.Cmd
	)

	// Allows scrolling to the bottom to reattach to most recent messages
	if m.viewport.AtBottom() {
		m.sticky = true
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			// Clean up processes before exiting
			cleanupProcesses(m.processes)
			return m, tea.Quit
		case "tab":
			m.activeTab = (m.activeTab + 1) % len(m.tabs)
			m.sticky = true
		case "shift+tab":
			m.activeTab = (m.activeTab - 1 + len(m.tabs)) % len(m.tabs)
		case "up":
			m.sticky = false
		case "s":
			m.sticky = true
		case "t":
			m.sticky = false
			m.viewport.GotoTop()
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

	content := m.outputs[m.activeTab]
	m.viewport.SetContent(content)
	if m.sticky {
		m.viewport.GotoBottom()
	}

	m.viewport, cmd = m.viewport.Update(msg)

	cmds = append(cmds, cmd)
	return m, tea.Batch(cmds...)
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

	helpView := m.help.View(m.keys)

	return fmt.Sprintf(
		"%s\n%s\n%s\n%s",
		tabRow,
		strings.Repeat("─", m.viewport.Width),
		m.viewport.View(),
		helpView,
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

func cleanupProcesses(processes []Process) {
	for _, p := range processes {
		if p.cmd != nil && p.cmd.Process != nil {
			if p.cmd.Process.Pid > 0 {
				syscall.Kill(-p.cmd.Process.Pid, syscall.SIGKILL)
			}
			p.cmd.Process.Kill()
			p.cmd.Wait()
		}
	}
}

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

	m := initialModel(processes)

	prog := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := prog.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
		os.Exit(1)
	}
}
