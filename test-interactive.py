#!/usr/bin/env python3
"""
Test script to simulate interactive mode selection and trigger processing
to see if progress bars work in the UI mode.
"""

import subprocess
import time
import signal
import sys
import os

def test_interactive_progress():
    print("🧪 Testing interactive mode progress bars...")
    
    # Start the interactive program in background
    try:
        # Use script to simulate a terminal
        proc = subprocess.Popen(
            ['script', '-qec', './vns-generator', '/dev/null'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            preexec_fn=os.setsid
        )
        
        # Give it time to load regions
        time.sleep(3)
        
        # Send commands to select a region and start processing
        commands = [
            "/",          # Start filtering
            "albania",    # Type albania  
            "\n",         # Confirm filter
            " ",          # Select the region
            "\n",         # Start processing
        ]
        
        for cmd in commands:
            proc.stdin.write(cmd)
            proc.stdin.flush()
            time.sleep(0.5)
        
        # Wait for processing to start and capture output
        time.sleep(5)
        
        # Kill the process
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        
        # Get output
        stdout, _ = proc.communicate(timeout=2)
        print("📋 Interactive mode output:")
        print(stdout)
        
        # Check if progress bars appeared
        if "Overall Progress:" in stdout or "Step Progress:" in stdout:
            print("✅ Progress bars found in interactive mode!")
            return True
        else:
            print("❌ Progress bars NOT found in interactive mode")
            return False
            
    except Exception as e:
        print(f"❌ Test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_interactive_progress()
    sys.exit(0 if success else 1)