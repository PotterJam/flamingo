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
VITE_PORT_1 = 5173  # First Vite instance port
VITE_PORT_2 = 5174  # Second Vite instance port
BACKEND_PORT = 8080
# --- End Configuration ---

# --- Globals ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
frontend_path = os.path.join(SCRIPT_DIR, FRONTEND_DIR)
backend_path = os.path.join(SCRIPT_DIR, BACKEND_DIR)

frontend_process_1 = None
frontend_process_2 = None
backend_process = None
stop_event = threading.Event()

def run_command(cmd, cwd, step_name):
    """Runs a command in a subprocess and checks for errors."""
    print(f"\n--- Running Step: {step_name} ---")
    print(f"Executing: {' '.join(cmd)} in {cwd}")
    try:
        use_shell = sys.platform == "win32"
        result = subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True, shell=use_shell, encoding='utf-8', errors='replace')
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

def start_frontend():
    """Starts two Vite dev server instances."""
    global frontend_process_1, frontend_process_2
    print("\n--- Starting Frontend Dev Servers ---")
    try:
        # Start first Vite instance
        env_1 = os.environ.copy()
        env_1['PORT'] = str(VITE_PORT_1)
        frontend_process_1 = subprocess.Popen(
            ["npm", "run", "dev"],
            cwd=frontend_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True,
            env=env_1
        )
        print(f"First frontend dev server started on port {VITE_PORT_1}")

        # Start second Vite instance
        env_2 = os.environ.copy()
        env_2['PORT'] = str(VITE_PORT_2)
        frontend_process_2 = subprocess.Popen(
            ["npm", "run", "dev"],
            cwd=frontend_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True,
            env=env_2
        )
        print(f"Second frontend dev server started on port {VITE_PORT_2}")
        return True
    except Exception as e:
        print(f"!!! ERROR starting frontend dev servers: {e} !!!")
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
        return True
    except Exception as e:
        print(f"!!! ERROR starting backend server: {e} !!!")
        return False

def stop_processes():
    """Stops all processes."""
    global frontend_process_1, frontend_process_2, backend_process
    if frontend_process_1:
        print("\n--- Stopping First Frontend Dev Server ---")
        frontend_process_1.terminate()
        frontend_process_1.wait()
        frontend_process_1 = None
    if frontend_process_2:
        print("\n--- Stopping Second Frontend Dev Server ---")
        frontend_process_2.terminate()
        frontend_process_2.wait()
        frontend_process_2 = None
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
        print("Failed to start frontend servers. Exiting.")
        sys.exit(1)
    
    if not start_backend():
        print("Failed to start backend. Exiting.")
        stop_processes()
        sys.exit(1)

    # Give servers a moment to start up
    time.sleep(2)

    # Open browser tabs to each Vite instance
    try:
        print(f"\nOpening browser tabs to http://localhost:{VITE_PORT_1} and http://localhost:{VITE_PORT_2}...")
        webbrowser.open_new_tab(f"http://localhost:{VITE_PORT_1}")
        time.sleep(0.5)
        webbrowser.open_new_tab(f"http://localhost:{VITE_PORT_2}")
    except Exception as e:
        print(f"Warning: Could not open browser tabs automatically: {e}")

    print("\n--- Development servers running ---")
    print(f"Frontend 1: http://localhost:{VITE_PORT_1}")
    print(f"Frontend 2: http://localhost:{VITE_PORT_2}")
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
