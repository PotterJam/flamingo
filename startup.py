import subprocess
import os
import shutil
import time
import webbrowser
import sys
import signal

# --- Configuration ---
FRONTEND_DIR = "frontend"
BACKEND_DIR = "backend"
# Svelte's build output directory (relative to FRONTEND_DIR)
SVELTE_BUILD_DIR_NAME = "dist"
# Directory where Go backend expects frontend assets (relative to BACKEND_DIR)
GO_PUBLIC_DIR_NAME = "public"
# Name for the compiled Go executable
GO_EXE_NAME = "scriblio_server"
# Port the Go server listens on
SERVER_PORT = 8080
# Frontend build command (use 'pnpm build' if you use pnpm)
FRONTEND_BUILD_CMD = ["npm", "run", "build"]
# --- End Configuration ---

# Get absolute paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
frontend_path = os.path.join(SCRIPT_DIR, FRONTEND_DIR)
backend_path = os.path.join(SCRIPT_DIR, BACKEND_DIR)
svelte_build_path = os.path.join(frontend_path, SVELTE_BUILD_DIR_NAME)
go_public_path = os.path.join(backend_path, GO_PUBLIC_DIR_NAME)
go_exe_path = os.path.join(backend_path, GO_EXE_NAME + (".exe" if sys.platform == "win32" else ""))

server_process = None # To store the server process

def run_command(cmd, cwd, step_name):
    """Runs a command in a subprocess and checks for errors."""
    print(f"--- Running Step: {step_name} ---")
    print(f"Executing: {' '.join(cmd)} in {cwd}")
    try:
        # Use shell=True only if necessary (e.g., complex commands), otherwise False is safer
        use_shell = sys.platform == "win32" # npm/pnpm might need shell on Windows
        result = subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True, shell=use_shell)
        print(result.stdout)
        print(f"--- {step_name} Successful ---")
        return True
    except subprocess.CalledProcessError as e:
        print(f"!!! ERROR during {step_name} !!!")
        print(f"Command: {' '.join(e.cmd)}")
        print(f"Return Code: {e.returncode}")
        print("--- STDOUT ---")
        print(e.stdout)
        print("--- STDERR ---")
        print(e.stderr)
        return False
    except FileNotFoundError:
        print(f"!!! ERROR during {step_name} !!!")
        print(f"Command not found: {cmd[0]}. Is it installed and in your PATH?")
        return False

def cleanup():
    """Stops the server process if it's running."""
    global server_process
    if server_process and server_process.poll() is None: # Check if process exists and is running
        print(f"\n--- Stopping Go server (PID: {server_process.pid}) ---")
        try:
            # Graceful termination first
            if sys.platform == "win32":
                server_process.send_signal(signal.CTRL_C_EVENT) # Simulate Ctrl+C on Windows
            else:
                 server_process.terminate() # SIGTERM on Unix-like

            # Wait a bit
            server_process.wait(timeout=5)
            print("Server terminated gracefully.")
        except subprocess.TimeoutExpired:
            print("Server did not terminate gracefully, forcing kill.")
            server_process.kill() # Force kill if terminate fails
            server_process.wait()
            print("Server killed.")
        except Exception as e:
             print(f"Error stopping server: {e}")
             print("You might need to stop the process manually.")
             print(f"PID: {server_process.pid}")
    else:
        print("\n--- Server not running or already stopped ---")

def main():
    global server_process
    try:
        # 1. Build Frontend
        if not run_command(FRONTEND_BUILD_CMD, frontend_path, "Build Svelte Frontend"):
            sys.exit(1)

        # 2. Prepare Backend Public Directory
        print("--- Running Step: Prepare Go Public Directory ---")
        if os.path.exists(go_public_path):
            print(f"Removing existing directory: {go_public_path}")
            shutil.rmtree(go_public_path)

        if not os.path.exists(svelte_build_path):
             print(f"!!! ERROR: Svelte build output directory not found: {svelte_build_path}")
             sys.exit(1)

        print(f"Copying '{svelte_build_path}' to '{go_public_path}'")
        shutil.copytree(svelte_build_path, go_public_path)
        print("--- Prepare Go Public Directory Successful ---")

        # 3. Build Backend
        go_build_cmd = ["go", "build", "-o", GO_EXE_NAME, "."]
        if not run_command(go_build_cmd, backend_path, "Build Go Backend"):
            sys.exit(1)

        # 4. Run Backend
        print("--- Running Step: Start Go Server ---")
        print(f"Starting server: {go_exe_path}")
        try:
            # Start the server as a background process
            # Run it from within the backend directory so it finds ./public
            server_process = subprocess.Popen([go_exe_path], cwd=backend_path)
            print(f"Server started successfully with PID: {server_process.pid}")
        except Exception as e:
            print(f"!!! ERROR starting Go server: {e} !!!")
            sys.exit(1)

        # 5. Wait and Open Browsers
        print("\nWaiting for server to initialize...")
        time.sleep(3) # Give the server a few seconds to start

        server_url = f"http://localhost:{SERVER_PORT}"
        print(f"Opening two browser tabs to {server_url} ...")
        try:
            webbrowser.open_new_tab(server_url)
            time.sleep(0.5) # Small delay between opening tabs
            webbrowser.open_new_tab(server_url)
            print("Browser tabs opened.")
        except Exception as e:
            print(f"Warning: Could not open browser tabs automatically: {e}")
            print(f"Please open two tabs manually to: {server_url}")

        # 6. Inform User
        print("\n--- Setup Complete ---")
        print("The Go server is running in the background.")
        print("Two browser tabs should be open, simulating two players.")
        print(f"To STOP the server, press CTRL+C in this terminal.")

        # Keep the script running until interrupted
        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\nCtrl+C received.")
    finally:
        # Ensure cleanup runs on exit or interrupt
        cleanup()
        print("--- Script Finished ---")


if __name__ == "__main__":
    main()


# **How to Use:**

# 1.  Save the code above as a Python file (e.g., `start_game.py`) in the **parent directory** that contains your `frontend` and `backend` folders.
# 2.  Make sure your project structure looks like this:

#     ```
#     your_project_root/
#     ├── start_game.py  <-- Save the script here
#     ├── backend/
#     │   ├── main.go
#     │   ├── hub.go     (and other .go files)
#     │   └── go.mod
#     │   └── go.sum
#     └── frontend/
#         ├── src/
#         ├── public/
#         ├── package.json
#         ├── vite.config.js (or similar)
#         └── ... (other svelte files)
#     ```

# 3.  Open your terminal or command prompt.
# 4.  Navigate **into** the `your_project_root` directory.
# 5.  Run the script: `python start_game.py`
# 6.  The script will execute the build steps, start the server, and open browser tabs.
# 7.  When you are finished testing, go back to the terminal where the Python script is running and press `Ctrl+C`. The script will attempt to stop the Go server process automatical
