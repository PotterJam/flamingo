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

The easiest way to run the application is to use `compound`, the compound process manager we created to help with this project.

Simply navitate to the root of the project and run `./compund/compound`.

### Development Features

* **Frontend Hot Reloading:** Any changes to frontend code will be immediately reflected in the browser
* **Backend Hot Reloading:** Any changes to backend code will automatically restart the server. You will need to restart your browser tabs manually.
* **WebSocket Support:** The development server properly handles WebSocket connections
* **API Proxying:** Frontend API requests are automatically proxied to the backend server
    * The Vite dev server runs on port 5173
    * The Go backend runs on port 8080
    * All API and WebSocket requests are automatically proxied from the frontend to the backend
