import subprocess
import os
import shutil
import time
import webbrowser
import sys
import signal
import threading

# --- Configuration ---
FRONTEND_DIR = "frontend" # Or "frontend" if using Svelte
BACKEND_DIR = "backend"
BUILD_OUTPUT_DIR_NAME = "dist"
GO_PUBLIC_DIR_NAME = "public"
GO_EXE_NAME = "scriblio_server"
SERVER_PORT = 8080
# Use correct build command based on your frontend (npm/pnpm)
FRONTEND_BUILD_CMD = ["npm", "run", "build"]
# --- End Configuration ---

# --- Globals ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
frontend_path = os.path.join(SCRIPT_DIR, FRONTEND_DIR)
backend_path = os.path.join(SCRIPT_DIR, BACKEND_DIR)
build_output_path = os.path.join(frontend_path, BUILD_OUTPUT_DIR_NAME)
go_public_path = os.path.join(backend_path, GO_PUBLIC_DIR_NAME)
# Determine executable path based on OS
go_exe_filename = GO_EXE_NAME + (".exe" if sys.platform == "win32" else "")
go_exe_path = os.path.join(backend_path, go_exe_filename)

server_process = None # Process handle for the Go backend
server_lock = threading.Lock() # To protect access to server_process
stop_event = threading.Event() # To signal exit to the input loop

# --- Helper Functions ---

def run_command(cmd, cwd, step_name):
    """Runs a command in a subprocess and checks for errors."""
    print(f"\n--- Running Step: {step_name} ---")
    print(f"Executing: {' '.join(cmd)} in {cwd}")
    try:
        use_shell = sys.platform == "win32" # Needed for npm/pnpm on Windows?
        result = subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True, shell=use_shell, encoding='utf-8', errors='replace')
        # Only print stdout if it's not excessively long
        if len(result.stdout) < 2000:
             print(result.stdout)
        else:
             print(f"(stdout too long, truncated)")
        if result.stderr:
             print("--- STDERR ---")
             print(result.stderr)
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
    except Exception as e:
        print(f"!!! UNEXPECTED ERROR during {step_name}: {e} !!!")
        return False

def build_frontend():
    """Builds the frontend application."""
    return run_command(FRONTEND_BUILD_CMD, frontend_path, "Build Frontend")

def copy_frontend():
    """Copies the built frontend assets to the backend public directory."""
    print("\n--- Running Step: Prepare Go Public Directory ---")
    if os.path.exists(go_public_path):
        print(f"Removing existing directory: {go_public_path}")
        try:
            shutil.rmtree(go_public_path)
        except OSError as e:
            print(f"!!! ERROR removing directory {go_public_path}: {e}")
            return False

    if not os.path.exists(build_output_path):
         print(f"!!! ERROR: Frontend build output directory not found: {build_output_path}")
         return False

    print(f"Copying '{build_output_path}' to '{go_public_path}'")
    try:
        shutil.copytree(build_output_path, go_public_path)
        print("--- Prepare Go Public Directory Successful ---")
        return True
    except OSError as e:
        print(f"!!! ERROR copying directory: {e}")
        return False

def build_backend():
    """Builds the Go backend executable."""
    # Use os.path.join for cross-platform compatibility when specifying output
    go_build_cmd = ["go", "build", "-o", go_exe_path, "."]
    # The command needs to run *in* the backend directory
    return run_command(go_build_cmd, backend_path, "Build Go Backend")

def stop_backend():
    """Stops the running Go backend process."""
    global server_process
    with server_lock: # Protect access to server_process
        if server_process and server_process.poll() is None: # Check if process exists and is running
            print(f"\n--- Stopping Go server (PID: {server_process.pid}) ---")
            try:
                # Graceful termination first
                if sys.platform == "win32":
                    # Sending CTRL_C_EVENT requires process group handling often
                    # os.kill(server_process.pid, signal.CTRL_C_EVENT) # More complex
                    # Try terminate/kill first on windows too
                    server_process.terminate()
                else:
                     server_process.terminate() # SIGTERM on Unix-like

                try:
                    server_process.wait(timeout=5) # Wait up to 5 seconds
                    print("Server terminated gracefully.")
                except subprocess.TimeoutExpired:
                    print("Server did not terminate gracefully, forcing kill.")
                    server_process.kill() # Force kill if terminate fails
                    server_process.wait() # Wait for kill to complete
                    print("Server killed.")
                server_process = None # Clear the process handle
                return True
            except Exception as e:
                 print(f"Error stopping server: {e}")
                 print("You might need to stop the process manually.")
                 print(f"PID: {server_process.pid}")
                 # Keep server_process handle? Maybe it's still alive? Risky.
                 server_process = None # Assume it's gone or unusable
                 return False
        else:
            print("\n--- Server not running or already stopped ---")
            server_process = None # Ensure handle is cleared
            return True # Considered successful if already stopped

def start_backend(open_browser=False):
    """Starts the Go backend process."""
    global server_process
    with server_lock: # Protect access
        if server_process and server_process.poll() is None:
            print("--- Server already running ---")
            return False # Indicate it wasn't started now

        print("\n--- Running Step: Start Go Server ---")
        if not os.path.exists(go_exe_path):
            print(f"!!! ERROR: Go executable not found: {go_exe_path}")
            print("--- Please build the backend first ('b' then 's' or 'r' then 's') ---")
            return False

        print(f"Starting server: {go_exe_path}")
        try:
            # Start the server as a background process
            server_process = subprocess.Popen([go_exe_path], cwd=backend_path)
            print(f"Server started successfully with PID: {server_process.pid}")
            time.sleep(2) # Give server a moment to initialize

            if open_browser:
                server_url = f"http://localhost:{SERVER_PORT}"
                print(f"Opening two browser tabs to {server_url} ...")
                try:
                    webbrowser.open_new_tab(server_url)
                    time.sleep(0.5)
                    webbrowser.open_new_tab(server_url)
                    print("Browser tabs opened.")
                except Exception as e:
                    print(f"Warning: Could not open browser tabs automatically: {e}")
                    print(f"Please open tabs manually to: {server_url}")
            return True # Indicate successful start
        except Exception as e:
            print(f"!!! ERROR starting Go server: {e} !!!")
            server_process = None # Ensure handle is cleared on error
            return False

# --- Main Loop ---

def display_menu():
    print("\n----- Options -----")
    print("  r : Restart All (Frontend Build + Backend Build & Run)")
    print("  f : Restart Frontend (Frontend Build only - Refresh Browser Manually)")
    print("  b : Restart Backend (Backend Build & Run)")
    print("  s : Start Backend (if stopped)")
    print("  k : Kill Backend (if running)")
    print("  o : Open Browser Tabs")
    print("  q : Quit")
    print("-------------------")
    print("Enter command: ", end='', flush=True)

def main_interactive_loop():
    """Handles user input for interactive control."""
    while not stop_event.is_set():
        display_menu()
        try:
            command = input().lower().strip()
            if not command:
                continue

            if command == 'r':
                print("\n>>> Restarting All...")
                if stop_backend():
                    if build_frontend() and copy_frontend() and build_backend():
                        start_backend()
                    else:
                        print("!!! ERROR during restart all sequence. Backend may not be running.")
                else:
                    print("!!! ERROR stopping backend during restart all.")

            elif command == 'f':
                print("\n>>> Restarting Frontend...")
                if build_frontend() and copy_frontend():
                     print("--- Frontend rebuilt. Please REFRESH your browser tabs! ---")
                else:
                     print("!!! ERROR during frontend restart sequence.")

            elif command == 'b':
                print("\n>>> Restarting Backend...")
                if stop_backend():
                    if build_backend():
                        start_backend()
                    else:
                        print("!!! ERROR building backend during restart.")
                else:
                     print("!!! ERROR stopping backend during restart.")

            elif command == 's':
                 print("\n>>> Starting Backend...")
                 start_backend()

            elif command == 'k':
                 print("\n>>> Killing Backend...")
                 stop_backend()

            elif command == 'o':
                 print("\n>>> Opening Browser Tabs...")
                 server_url = f"http://localhost:{SERVER_PORT}"
                 try:
                    webbrowser.open_new_tab(server_url)
                    time.sleep(0.5)
                    webbrowser.open_new_tab(server_url)
                    print("Browser tabs opened.")
                 except Exception as e:
                    print(f"Warning: Could not open browser tabs automatically: {e}")

            elif command == 'q':
                print("\n>>> Quitting...")
                stop_event.set() # Signal loop to exit
            else:
                print(f"\nUnknown command: '{command}'")

        except EOFError: # Handle Ctrl+D
             print("\nEOF received, quitting...")
             stop_event.set()
        except KeyboardInterrupt: # Handle Ctrl+C in input()
             print("\nCtrl+C received, quitting...")
             stop_event.set()
        except Exception as e:
             print(f"\n!!! Error in input loop: {e} !!!")


if __name__ == "__main__":
    print("--- Initial Setup ---")
    # 1. Initial Frontend Build
    if not build_frontend():
        sys.exit(1)
    # 2. Initial Copy
    if not copy_frontend():
        sys.exit(1)
    # 3. Initial Backend Build
    if not build_backend():
        sys.exit(1)
    # 4. Initial Backend Start
    if not start_backend(open_browser=True):
        print("!!! Initial backend start failed. Exiting. !!!")
        sys.exit(1)

    print("\n--- Setup Complete ---")
    print("Backend server is running in the background.")

    # Start interactive loop in main thread
    try:
         main_interactive_loop()
    finally:
         # Ensure cleanup runs on any exit from the loop
         print("\n--- Exiting ---")
         stop_backend()
         print("--- Script Finished ---")
