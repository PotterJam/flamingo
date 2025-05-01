# Flamingo: a drawing game

## Features (Current)
* **Multiplayer:** Supports multiple players joining a single game session.
* **Real-time Drawing:** See what the drawer draws instantly via WebSockets.
* **Simultaneous Guessing:** All non-drawers can guess at the same time.
* **Turn-Based Gameplay:** Players take turns drawing in a round-robin fashion.
* **Host Control:** The first player to join becomes the host and controls when the game starts.
* **Timed Turns:** Each drawing turn has a timer.
* **Basic Chat:** Displays incorrect guesses and system messages.
* **Correct Guess Indication:** Highlights players who have guessed correctly in the player list.

## Technology Stack

* **Backend:** Go (Golang)
    * WebSockets: `gorilla/websocket`
    * Routing: `gorilla/mux`
    * Hot Reloading: `air`
* **Frontend:** React (using Vite)
    * Styling: `Tailwind CSS`
    * State Management: `Zustand`
* **Build/Run Script:** Python 3

## Prerequisites

* **Go:** Version 1.24 ([https://go.dev/doc/install](https://go.dev/doc/install)).
    * Add Go's bin directory to your PATH:
        ```bash
        # For fish shell (add to ~/.config/fish/config.fish):
        set -U fish_user_paths $fish_user_paths $HOME/go/bin
        
        # For bash/zsh (add to ~/.bashrc or ~/.zshrc):
        export PATH=$PATH:$HOME/go/bin
        ```
* **Node.js & npm (or pnpm):** Latest LTS version recommended ([https://nodejs.org/](https://nodejs.org/)). Used for the React frontend.
* **Python 3:** Used for the startup script ([https://www.python.org/downloads/](https://www.python.org/downloads/)).

## Setup

1. **Backend Dependencies:** Navigate to the `backend` directory and resolve Go modules.
    ```bash
    go mod tidy
    ```
2. **Install Air for Go hot reloading:**
    ```bash
    go install github.com/air-verse/air@latest
    ```
3. **Frontend Dependencies:** Navigate to the frontend directory and install Node modules.
    ```bash
    npm install
    ```

## Running the Application

The easiest way to run both the frontend and backend with hot reloading is using the provided Python script.

1. **Navigate** to the root directory of the project
2. **Run the script:**
    ```bash
    python startup.py
    ```
3. The script will:
    * Start two Vite dev server instances for frontend hot reloading:
        * First instance on port 5173
        * Second instance on port 5174
    * Start the Go backend with Air for backend hot reloading (port 8080)
    * Attempt to open two browser tabs, one to each frontend instance
4. **Enter Names:** Enter a unique name in each browser tab when prompted.
5. **Start Game:** The first player (Host) will see a "Start Game" button once at least two players have joined. Click it to begin the first round.

### Development Features

* **Independent Frontend Instances:** Two separate Vite dev servers run to support multiple players
* **Frontend Hot Reloading:** Any changes to frontend code will be immediately reflected in both browser instances
* **Backend Hot Reloading:** Any changes to backend code will automatically restart the server
* **WebSocket Support:** Each frontend instance maintains its own WebSocket connection
* **API Proxying:** Frontend API requests are automatically proxied to the backend server
    * Frontend instances run on ports 5173 and 5174
    * The Go backend runs on port 8080
    * All API and WebSocket requests are automatically proxied from both frontends to the backend
