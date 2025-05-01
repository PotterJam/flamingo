import subprocess
import os
import sys
import webbrowser
import time
import threading
import signal

# --- Configuration ---
FRONTEND_DIR = "frontend"
BACKEND_DIR = "backend"
VITE_PORT = 5173  # Vite dev server port
BACKEND_PORT = 8080
# --- End Configuration ---

# --- Globals ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
frontend_path = os.path.join(SCRIPT_DIR, FRONTEND_DIR)
backend_path = os.path.join(SCRIPT_DIR, BACKEND_DIR)

frontend_process = None
backend_process = None
stop_event = threading.Event()

def print_output(process, prefix):
    """Print output from a process in real-time."""
    while not stop_event.is_set():
        if process.poll() is not None:
            break
        try:
            # Read from stdout
            line = process.stdout.readline()
            if line:
                print(f"[{prefix}] {line.rstrip()}")
            # Read from stderr
            line = process.stderr.readline()
            if line:
                print(f"[{prefix} ERROR] {line.rstrip()}", file=sys.stderr)
        except Exception:
            break

def start_frontend():
    """Starts the Vite dev server."""
    global frontend_process
    print("\n--- Starting Frontend Dev Server ---")
    try:
        frontend_process = subprocess.Popen(
            ["npm", "run", "dev"],
            cwd=frontend_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        print(f"Frontend dev server started on port {VITE_PORT}")
        threading.Thread(target=print_output, args=(frontend_process, "Frontend"), daemon=True).start()
        return True
    except Exception as e:
        print(f"!!! ERROR starting frontend dev server: {e} !!!")
        return False

def start_backend():
    """Starts the Go backend with Air for hot reloading."""
    global backend_process
    print("\n--- Starting Backend with Air ---")
    try:
        backend_process = subprocess.Popen(
            ["air"],
            cwd=backend_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        print("Backend server started with hot reloading")
        threading.Thread(target=print_output, args=(backend_process, "Backend"), daemon=True).start()
        return True
    except Exception as e:
        print(f"!!! ERROR starting backend server: {e} !!!")
        return False

def stop_processes():
    """Stops all processes."""
    global frontend_process, backend_process
    if frontend_process:
        print("\n--- Stopping Frontend Dev Server ---")
        frontend_process.terminate()
        frontend_process.wait()
        frontend_process = None
    if backend_process:
        print("\n--- Stopping Backend Server ---")
        backend_process.terminate()
        backend_process.wait()
        backend_process = None

def signal_handler(sig, frame):
    """Handles termination signals."""
    print("\n--- Received termination signal ---")
    stop_event.set()
    stop_processes()
    sys.exit(0)

def main():
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start both servers
    if not start_frontend():
        print("Failed to start frontend server. Exiting.")
        sys.exit(1)
    
    if not start_backend():
        print("Failed to start backend. Exiting.")
        stop_processes()
        sys.exit(1)

    # Give servers a moment to start up
    time.sleep(2)

    # Open browser tabs to the Vite instance
    try:
        print(f"\nOpening browser tabs to http://localhost:{VITE_PORT}...")
        webbrowser.open_new_tab(f"http://localhost:{VITE_PORT}")
        time.sleep(0.5)
        webbrowser.open_new_tab(f"http://localhost:{VITE_PORT}")
    except Exception as e:
        print(f"Warning: Could not open browser tabs automatically: {e}")

    print("\n--- Development servers running ---")
    print(f"Frontend: http://localhost:{VITE_PORT}")
    print(f"Backend: http://localhost:{BACKEND_PORT}")
    print("Press Ctrl+C to stop all servers")
    
    # Keep the script running
    try:
        while not stop_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        stop_processes()

if __name__ == "__main__":
    main()
