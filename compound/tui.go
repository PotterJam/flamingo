package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	activeTabBorder = lipgloss.Border{
		Top:         "─",
		Bottom:      " ",
		Left:        "│",
		Right:       "│",
		TopLeft:     "╭",
		TopRight:    "╮",
		BottomLeft:  "┘",
		BottomRight: "└",
	}

	tabBorder = lipgloss.Border{
		Top:         "─",
		Bottom:      "─",
		Left:        "│",
		Right:       "│",
		TopLeft:     "╭",
		TopRight:    "╮",
		BottomLeft:  "┴",
		BottomRight: "┴",
	}

	tabStyle = lipgloss.NewStyle().
			Border(tabBorder, true).
			BorderForeground(lipgloss.Color("62")).
			Padding(0, 1)

	tabGap = tabStyle.
		BorderTop(false).
		BorderLeft(false).
		BorderRight(false)
)

type keyMap struct {
	StickToBottom key.Binding
	GoToTop       key.Binding
	NextTab       key.Binding
	PrevTab       key.Binding
	Exit          key.Binding
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.StickToBottom,
		k.GoToTop,
		k.NextTab,
		k.PrevTab,
		k.Exit,
	}
}

func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.StickToBottom, k.GoToTop},
		{k.NextTab, k.PrevTab, k.Exit},
	}
}

type Model struct {
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
	width     int
	height    int
}

func InitialModel(procs []Process) Model {
	vp := viewport.New(0, 0)

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
		Exit: key.NewBinding(
			key.WithKeys("q"),
			key.WithHelp("q", "quit"),
		),
	}

	return Model{
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

func (m Model) Init() tea.Cmd {
	return doTick()
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
		m.width = msg.Width
		m.height = msg.Height

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

func (m Model) View() string {
	if !m.ready {
		return "\n  Initializing..."
	}

	var tabs []string
	for i, tab := range m.tabs {
		style := tabStyle
		if i == m.activeTab {
			style = style.Border(activeTabBorder, true)
		}
		tabs = append(tabs, style.Render(tab))
	}
	joinedTabs := lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
	gap := tabGap.Render(strings.Repeat(" ", max(0, m.width-lipgloss.Width(joinedTabs)-2)))
	tabRow := lipgloss.JoinHorizontal(lipgloss.Bottom, joinedTabs, gap)

	m.viewport.Style = lipgloss.NewStyle().
		BorderTop(false).
		BorderBottom(false)

	helpView := lipgloss.NewStyle().
		Padding(0, 1).
		Render(m.help.View(m.keys))

	return fmt.Sprintf(
		"%s\n%s\n%s",
		tabRow,
		m.viewport.View(),
		helpView,
	)
}
