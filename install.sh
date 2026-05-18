#!/usr/bin/env bash
# install.sh — one-shot setup for the Granola note sync.
#
# Idempotent: safe to re-run. Performs:
#   1. Create Python venv in ~/.granola-sync-venv/ and install dependencies
#   2. Generate and install a LaunchAgent plist from your actual $HOME
#   3. Print next-step instructions

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_LABEL="com.$(whoami).granola-sync"
PLIST_NAME="${PLIST_LABEL}.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
VENV_DIR="$HOME/.granola-sync-venv"
STATE_DIR="$HOME/Library/Application Support/granola-sync"

# Optional: override output folder via env var before running install.sh
# e.g.  GRANOLA_SYNC_OUTPUT="$HOME/Documents/My Notes" ./install.sh
OUTPUT_DIR="${GRANOLA_SYNC_OUTPUT:-$HOME/Documents/Granola Notes}"

cyan()  { printf "\033[36m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }

cd "$PROJECT_DIR"

# 1. Python venv + deps
cyan "==> Creating Python virtualenv at $VENV_DIR"
if [ ! -f "$VENV_DIR/bin/python" ]; then
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r requirements.txt
green "venv ready — dependencies installed"

# 2. Runtime state and log dirs
mkdir -p "$STATE_DIR/logs"
cp sync_granola.py requirements.txt "$STATE_DIR/"
green "Runtime files copied to $STATE_DIR"

# 3. Create output folder
mkdir -p "$OUTPUT_DIR"
green "Output folder: $OUTPUT_DIR"

# 4. Generate and install the LaunchAgent plist (uses $HOME, not a hardcoded username)
cyan "==> Generating and installing LaunchAgent ($PLIST_LABEL)"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${VENV_DIR}/bin/python</string>
        <string>${STATE_DIR}/sync_granola.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${STATE_DIR}</string>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>2</integer>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>7</integer>
    </dict>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>${STATE_DIR}/logs/launchd.log</string>

    <key>StandardErrorPath</key>
    <string>${STATE_DIR}/logs/launchd.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>GRANOLA_SYNC_OUTPUT</key>
        <string>${OUTPUT_DIR}</string>
    </dict>
</dict>
</plist>
EOF

# Reload (idempotent)
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load -w "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
green "LaunchAgent loaded — sync will run every Tuesday at 6:07 AM"

# 5. Instructions
echo
cyan "==> Setup complete. Verify everything is working:"
echo
echo "  Run a healthcheck:"
echo "    $VENV_DIR/bin/python '$STATE_DIR/sync_granola.py' --healthcheck"
echo
echo "  Dry-run to preview what would sync:"
echo "    $VENV_DIR/bin/python '$STATE_DIR/sync_granola.py' --dry-run"
echo
echo "  Full sync:"
echo "    $VENV_DIR/bin/python '$STATE_DIR/sync_granola.py'"
echo
echo "  Output will appear in: $OUTPUT_DIR"
echo
echo "  Optional — keep your Mac awake at 6:07 AM for the scheduled run:"
echo "    sudo pmset repeat wakeorpoweron MTWRFSU 06:05:00"
echo
green "Done."
