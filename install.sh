#!/bin/sh
#
# install.sh - Install wspe and register it as a macOS LaunchAgent
#
# Presumes that the wspe binary is already built (e.g. via 'cargo build --release').
#
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_LABEL="uk.co.samuelwall.wspe"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/${PLIST_LABEL}.plist"
DEFAULT_BIN_DIR="$HOME/.local/bin"
BIN_DIR="${INSTALL_DIR:-$DEFAULT_BIN_DIR}"
IN_PLACE=0
CUSTOM_BINARY=""

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Installs wspe and registers it as a macOS LaunchAgent to start automatically on system login.
Presumes that the wspe binary has already been built.

OPTIONS:
    --bin-dir <DIR>     Directory to install the binary to (default: \$HOME/.local/bin)
    --in-place          Point LaunchAgent directly to the pre-built binary without copying
    --binary <PATH>     Specify custom path to pre-built wspe binary
    -u, --uninstall     Unregister the LaunchAgent and remove installed files
    -h, --help          Show this help message

ENVIRONMENT VARIABLES:
    INSTALL_DIR         Overrides default installation directory (\$HOME/.local/bin)
    WSPE_BIN            Overrides path to pre-built binary

EOF
}

uninstall() {
    echo "==> Uninstalling wspe startup service..."

    # Stop and unregister from launchd
    echo "Stopping service in launchd..."
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || \
    launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

    # Terminate any running wspe instances
    pkill -x wspe 2>/dev/null || true
    rm -f "/tmp/wspe.pid" 2>/dev/null || true

    # Remove LaunchAgent plist
    if [ -f "$PLIST_PATH" ]; then
        rm -f "$PLIST_PATH"
        echo "Removed LaunchAgent plist: $PLIST_PATH"
    fi

    # Remove installed binary if it exists in the install dir
    if [ -f "$BIN_DIR/wspe" ]; then
        rm -f "$BIN_DIR/wspe"
        echo "Removed binary: $BIN_DIR/wspe"
    fi

    echo "==> wspe has been successfully uninstalled."
    exit 0
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --bin-dir)
            if [ -z "$2" ]; then
                echo "Error: --bin-dir requires a directory argument." >&2
                exit 1
            fi
            BIN_DIR="$2"
            shift 2
            ;;
        --in-place)
            IN_PLACE=1
            shift
            ;;
        --binary)
            if [ -z "$2" ]; then
                echo "Error: --binary requires a path argument." >&2
                exit 1
            fi
            CUSTOM_BINARY="$2"
            shift 2
            ;;
        -u|--uninstall)
            uninstall
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'." >&2
            echo "Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
done

echo "==> Setting up wspe startup service..."

# 1. Locate pre-built binary
SOURCE_BIN=""
if [ -n "$CUSTOM_BINARY" ]; then
    SOURCE_BIN="$CUSTOM_BINARY"
elif [ -n "$WSPE_BIN" ]; then
    SOURCE_BIN="$WSPE_BIN"
elif [ -f "$PROJECT_DIR/target/release/wspe" ]; then
    SOURCE_BIN="$PROJECT_DIR/target/release/wspe"
elif [ -f "$PROJECT_DIR/target/debug/wspe" ]; then
    SOURCE_BIN="$PROJECT_DIR/target/debug/wspe"
elif command -v wspe >/dev/null 2>&1; then
    SOURCE_BIN="$(command -v wspe)"
fi

if [ -z "$SOURCE_BIN" ] || [ ! -f "$SOURCE_BIN" ]; then
    echo "Error: Pre-built wspe binary not found!" >&2
    echo "" >&2
    echo "This install script presumes that the application is already built." >&2
    echo "Please build the project first:" >&2
    echo "    cargo build --release" >&2
    echo "" >&2
    echo "Or specify the binary explicitly:" >&2
    echo "    $0 --binary /path/to/wspe" >&2
    echo "    or: WSPE_BIN=/path/to/wspe $0" >&2
    exit 1
fi

echo "Found pre-built binary: $SOURCE_BIN"

# 2. Determine target binary path
if [ "$IN_PLACE" -eq 1 ]; then
    TARGET_BIN="$(cd "$(dirname "$SOURCE_BIN")" && pwd)/$(basename "$SOURCE_BIN")"
    echo "Using binary in-place: $TARGET_BIN"
else
    echo "Installing binary to $BIN_DIR/wspe..."
    mkdir -p "$BIN_DIR"
    cp "$SOURCE_BIN" "$BIN_DIR/wspe"
    chmod +x "$BIN_DIR/wspe"
    TARGET_BIN="$BIN_DIR/wspe"
fi

# 3. Stop any existing wspe process or loaded agent
echo "Stopping any existing wspe instances..."
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || \
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
launchctl unload "$PLIST_PATH" 2>/dev/null || true

pkill -x wspe 2>/dev/null || true
rm -f "/tmp/wspe.pid" 2>/dev/null || true
sleep 0.5

# 4. Create LaunchAgent plist
echo "Creating LaunchAgent plist at $PLIST_PATH..."
mkdir -p "$LAUNCH_AGENTS_DIR"

cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>StandardOutPath</key>
    <string>/tmp/wspe.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wspe.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$TARGET_BIN")</string>
    </dict>
</dict>
</plist>
EOF

# 5. Register with launchd
echo "Registering and loading LaunchAgent..."
LOADED=0
if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null; then
    LOADED=1
elif launchctl load -w "$PLIST_PATH" 2>/dev/null; then
    LOADED=1
fi

if [ $LOADED -eq 1 ]; then
    echo "LaunchAgent successfully registered."
else
    echo "Notice: Could not load immediately via launchctl (may need terminal session or restart)."
    echo "You can try loading manually with:"
    echo "    launchctl bootstrap gui/$(id -u) $PLIST_PATH"
fi

sleep 1

if pgrep -x wspe >/dev/null 2>&1; then
    echo "wspe is running (PID: $(pgrep -x wspe | tr '\n' ' '))."
else
    echo "wspe is registered to launch automatically on login."
fi

echo ""
echo "================================================================="
echo "                  wspe Installation Complete                     "
echo "================================================================="
echo "Binary:        $TARGET_BIN"
echo "LaunchAgent:   $PLIST_PATH"
echo "Logs:          /tmp/wspe.log"
echo ""
echo "Permissions Notice:"
echo "wspe requires Accessibility and Automation permissions to switch spaces."
echo "If wspe was not previously granted permissions, please ensure:"
echo "  1. System Settings -> Privacy & Security -> Accessibility"
echo "     Enable: $TARGET_BIN"
echo "     (Press Cmd + Shift + . in file dialog if needed to see hidden files)"
echo "  2. System Settings -> Privacy & Security -> Automation"
echo "     Ensure System Events is enabled for wspe (prompted on first switch)"
echo ""
echo "Management commands:"
echo "  Check logs:    tail -f /tmp/wspe.log"
echo "  Uninstall:     ./install.sh --uninstall (or ./uninstall.sh)"
echo "================================================================="
