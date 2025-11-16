#!/usr/bin/env python3
"""
Test Python Application
Demonstrates that the application is running with visual feedback
"""

import time
import sys
from datetime import datetime


def animated_loading(duration=3):
    """Display an animated loading indicator"""
    chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    end_time = time.time() + duration
    i = 0

    while time.time() < end_time:
        sys.stdout.write(f'\r  {chars[i % len(chars)]} Starting up...')
        sys.stdout.flush()
        time.sleep(0.1)
        i += 1

    sys.stdout.write('\r  ✓ Startup complete!\n')
    sys.stdout.flush()


def main():
    """Main application entry point"""
    print("=" * 50)
    print("  TEST PYTHON APPLICATION")
    print("=" * 50)
    print()

    # Show startup animation
    animated_loading(2)
    print()

    # Display status information
    print("📊 Status Information:")
    print(f"  • Current time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  • Python version: {sys.version.split()[0]}")
    print(f"  • Application: RUNNING ✓")
    print()

    # Countdown demonstration
    print("⏱️  Running countdown test...")
    for i in range(5, 0, -1):
        sys.stdout.write(f'\r  Countdown: {i} seconds remaining...')
        sys.stdout.flush()
        time.sleep(1)

    print('\r  Countdown: Complete!          ')
    print()

    # Final status
    print("=" * 50)
    print("  ✓ Application is running successfully!")
    print("  All systems operational.")
    print("=" * 50)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Application stopped by user")
        sys.exit(0)
