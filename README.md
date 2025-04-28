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
* **Frontend:** React (using Vite)
    * Styling: Tailwind CSS
    * State Management: zustand
* **Build/Run Script:** Python 3

## Prerequisites

* **Go:** Version 1.24 ([https://go.dev/doc/install](https://go.dev/doc/install)).
* **Node.js & npm (or pnpm):** Latest LTS version recommended ([https://nodejs.org/](https://nodejs.org/)). Used for the React frontend.
* **Python 3:** Used for the startup script ([https://www.python.org/downloads/](https://www.python.org/downloads/)).

## Setup

1. **Backend Dependencies:** Navigate to the `backend` directory and resolve Go modules.
    ```bash
    go mod tidy
    ```
2.  **Frontend Dependencies:** Navigate to the frontend directory and install Node modules.
    ```bash
    npm install
    ```

## Running the Application

The easiest way to build and run both the frontend and backend is using the provided Python script.

**This will later be improved with HMR and a less hacked together script**

1.  **Navigate** to the root directory of the project
2.  **Run the script:**
    ```bash
    python start_game.py
    ```
3.  The script will:
    * Build the React frontend (`npm run build`).
    * Copy the built assets to the `backend/public` directory.
    * Build the Go backend executable.
    * Start the Go backend server.
    * Attempt to open two browser tabs to `http://localhost:8080`.
4.  **Enter Names:** Enter a unique name in each browser tab when prompted.
5.  **Start Game:** The first player (Host) will see a "Start Game" button once at least two players have joined. Click it to begin the first round.