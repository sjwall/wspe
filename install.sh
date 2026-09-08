#!/bin/sh
#
# install.sh - Install wspe and register it as a macOS LaunchAgent
#
# By default, downloads and installs the latest version from GitHub Releases.
# Also supports installing specific releases, local pre-built binaries,
# or running in-place.
#
set -e

REPO="sjwall/wspe"
PLIST_LABEL="uk.co.samuelwall.wspe"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/${PLIST_LABEL}.plist"
DEFAULT_BIN_DIR="$HOME/.local/bin"
BIN_DIR="$DEFAULT_BIN_DIR"
RELEASE_TAG=""
EXPLICIT_RELEASE=0
IN_PLACE=0
USE_LOCAL=0
CUSTOM_BINARY=""
ACTION="install"
TMP_DIR=""

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Installs wspe and registers it as a macOS LaunchAgent to start automatically on login.
By default, downloads and installs the latest release from GitHub ($REPO).

OPTIONS:
    -r, --release <TAG>   Release version/tag to install (e.g. 'v0.1.0-RC1' or 'latest', default: latest)
    -v, --version <TAG>   Alias for --release
    --bin-dir <DIR>       Directory to install the binary to (default: \$HOME/.local/bin)
    --local               Install local pre-built binary instead of downloading
    --in-place            Point LaunchAgent directly to pre-built binary without copying
    --binary <PATH>       Specify custom path to pre-built wspe binary
    -u, --uninstall       Unregister the LaunchAgent and remove installed files
    -h, --help            Show this help message

EXAMPLES:
    # Install latest release via curl
    curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/sjwall/wspe/main/install.sh | sh

    # Install specific release via curl
    curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/sjwall/wspe/main/install.sh | sh -s -- --release v0.1.0-RC1

    # Install latest release using local script
    ./install.sh

    # Install specific release using local script
    ./install.sh --release v0.1.0-RC1

    # Install from local build
    ./install.sh --local
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

resolve_latest_release() {
    # 1. Try URL redirect of /releases/latest (fastest, unauthenticated, no rate limit)
    LATEST_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
    RESOLVED="$(basename "$LATEST_URL")"
    if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "latest" ]; then
        echo "$RESOLVED"
        return 0
    fi

    # 2. Try GitHub API latest release
    API_RESPONSE="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
    RESOLVED="$(echo "$API_RESPONSE" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
    if [ -n "$RESOLVED" ]; then
        echo "$RESOLVED"
        return 0
    fi

    # 3. Fallback to HTML releases page (scrapes first tag link, no rate limit)
    RESOLVED="$(curl -fsSL "https://github.com/${REPO}/releases" 2>/dev/null | grep -o '/releases/tag/[^"'\''?]*' | head -n 1 | sed 's|/releases/tag/||')"
    if [ -n "$RESOLVED" ]; then
        echo "$RESOLVED"
        return 0
    fi

    # 4. Fallback to GitHub API list (for prereleases)
    API_RESPONSE="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" 2>/dev/null || true)"
    RESOLVED="$(echo "$API_RESPONSE" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
    if [ -n "$RESOLVED" ]; then
        echo "$RESOLVED"
        return 0
    fi

    return 1
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --release=*)
            RELEASE_TAG="${1#*=}"
            EXPLICIT_RELEASE=1
            shift
            ;;
        -r|--release|-v|--version)
            if [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
                echo "Error: $1 requires a release tag argument." >&2
                exit 1
            fi
            RELEASE_TAG="$2"
            EXPLICIT_RELEASE=1
            shift 2
            ;;
        --version=*)
            RELEASE_TAG="${1#*=}"
            EXPLICIT_RELEASE=1
            shift
            ;;
        --bin-dir=*)
            BIN_DIR="${1#*=}"
            shift
            ;;
        --bin-dir)
            if [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
                echo "Error: --bin-dir requires a directory argument." >&2
                exit 1
            fi
            BIN_DIR="$2"
            shift 2
            ;;
        --binary=*)
            CUSTOM_BINARY="${1#*=}"
            shift
            ;;
        --binary)
            if [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
                echo "Error: --binary requires a path argument." >&2
                exit 1
            fi
            CUSTOM_BINARY="$2"
            shift 2
            ;;
        --in-place)
            IN_PLACE=1
            shift
            ;;
        --local)
            USE_LOCAL=1
            shift
            ;;
        -u|--uninstall)
            ACTION="uninstall"
            shift
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

if [ "$ACTION" = "uninstall" ]; then
    uninstall
fi

if [ "$EXPLICIT_RELEASE" -eq 1 ] && [ -n "$CUSTOM_BINARY" ]; then
    echo "Error: Cannot specify both --release/--version and --binary." >&2
    exit 1
fi

if [ "$EXPLICIT_RELEASE" -eq 1 ] && [ "$IN_PLACE" -eq 1 ]; then
    echo "Error: Cannot specify both --release/--version and --in-place." >&2
    exit 1
fi

if [ "$EXPLICIT_RELEASE" -eq 1 ] && [ "$USE_LOCAL" -eq 1 ]; then
    echo "Error: Cannot specify both --release/--version and --local." >&2
    exit 1
fi

if [ -n "$CUSTOM_BINARY" ] && [ "$USE_LOCAL" -eq 1 ]; then
    echo "Error: Cannot specify both --binary and --local." >&2
    exit 1
fi

OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    echo "Error: wspe only supports macOS (Darwin), but detected OS: '$OS'." >&2
    exit 1
fi

echo "==> Setting up wspe startup service..."

# 1. Locate or download binary
SOURCE_BIN=""
PROJECT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

if [ -n "$CUSTOM_BINARY" ]; then
    if [ ! -f "$CUSTOM_BINARY" ]; then
        echo "Error: Specified binary does not exist: $CUSTOM_BINARY" >&2
        exit 1
    fi
    SOURCE_BIN="$CUSTOM_BINARY"
    echo "Using specified binary: $SOURCE_BIN"

elif [ "$IN_PLACE" -eq 1 ] || [ "$USE_LOCAL" -eq 1 ]; then
    if [ -f "$PROJECT_DIR/target/release/wspe" ]; then
        SOURCE_BIN="$PROJECT_DIR/target/release/wspe"
    elif [ -f "$PROJECT_DIR/target/debug/wspe" ]; then
        SOURCE_BIN="$PROJECT_DIR/target/debug/wspe"
    elif [ -f "$PROJECT_DIR/wspe" ]; then
        SOURCE_BIN="$PROJECT_DIR/wspe"
    elif command -v wspe >/dev/null 2>&1; then
        SOURCE_BIN="$(command -v wspe)"
    fi

    if [ -z "$SOURCE_BIN" ] || [ ! -f "$SOURCE_BIN" ]; then
        echo "Error: Local pre-built wspe binary not found!" >&2
        echo "Please build the project first:" >&2
        echo "    cargo build --release" >&2
        echo "" >&2
        echo "Or omit --local/--in-place to download from GitHub releases." >&2
        exit 1
    fi
    echo "Found local pre-built binary: $SOURCE_BIN"

elif [ "$EXPLICIT_RELEASE" -eq 0 ] && \
     [ "$0" != "sh" ] && [ "$0" != "-sh" ] && [ "$0" != "bash" ] && [ "$0" != "zsh" ] && \
     [ -f "$PROJECT_DIR/wspe" ] && [ -f "$PROJECT_DIR/LICENSE" ] && [ ! -d "$PROJECT_DIR/.git" ] && [ ! -f "$PROJECT_DIR/Cargo.toml" ]; then
    # Running from an unpacked release archive
    SOURCE_BIN="$PROJECT_DIR/wspe"
    echo "Using bundled release binary: $SOURCE_BIN"

else
    # Default: Download from GitHub Releases
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: 'curl' is required to download wspe." >&2
        exit 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
        echo "Error: 'tar' is required to extract wspe." >&2
        exit 1
    fi

    TAG="$RELEASE_TAG"
    if [ -z "$TAG" ] || [ "$TAG" = "latest" ]; then
        echo "==> Fetching latest release info for ${REPO}..."
        TAG="$(resolve_latest_release)" || true
    fi

    if [ -z "$TAG" ]; then
        echo "Error: Could not determine the release version to install from ${REPO}." >&2
        echo "Please specify a release version using: $0 --release <TAG>" >&2
        exit 1
    fi

    # Normalize tag (prepend 'v' if it starts with a digit)
    case "$TAG" in
        v*) ;;
        [0-9]*) TAG="v$TAG" ;;
    esac

    echo "Selected release: $TAG"

    # Architecture detection
    ARCH="$(uname -m)"
    if [ "$ARCH" = "x86_64" ] && [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
        ARCH="arm64"
    fi

    case "$ARCH" in
        arm64|aarch64)
            TARGET="aarch64-apple-darwin"
            ;;
        x86_64|amd64)
            TARGET="x86_64-apple-darwin"
            ;;
        *)
            TARGET="universal-apple-darwin"
            ;;
    esac

    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'wspe-install')"

    ASSET_NAME="wspe-${TAG}-${TARGET}.tar.gz"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"

    echo "==> Downloading wspe ${TAG} (${TARGET})..."
    if ! curl --proto '=https' --tlsv1.2 -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET_NAME"; then
        if [ "$TARGET" != "universal-apple-darwin" ]; then
            echo "Target-specific archive not found, trying universal binary..."
            TARGET="universal-apple-darwin"
            ASSET_NAME="wspe-${TAG}-${TARGET}.tar.gz"
            DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
            if ! curl --proto '=https' --tlsv1.2 -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET_NAME"; then
                echo "Error: Failed to download release asset for tag '${TAG}'." >&2
                echo "URL: $DOWNLOAD_URL" >&2
                exit 1
            fi
        else
            echo "Error: Failed to download release asset for tag '${TAG}'." >&2
            echo "URL: $DOWNLOAD_URL" >&2
            exit 1
        fi
    fi

    # Verify checksum if SHA256SUMS.txt is available
    CHECKSUM_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS.txt"
    if curl --proto '=https' --tlsv1.2 -fsSL "$CHECKSUM_URL" -o "$TMP_DIR/SHA256SUMS.txt" 2>/dev/null; then
        EXPECTED_SHA="$(grep "[[:space:]]${ASSET_NAME}\$" "$TMP_DIR/SHA256SUMS.txt" 2>/dev/null | awk '{print $1}')"
        if [ -n "$EXPECTED_SHA" ]; then
            if command -v shasum >/dev/null 2>&1; then
                ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/$ASSET_NAME" | awk '{print $1}')"
            elif command -v sha256sum >/dev/null 2>&1; then
                ACTUAL_SHA="$(sha256sum "$TMP_DIR/$ASSET_NAME" | awk '{print $1}')"
            else
                ACTUAL_SHA=""
            fi

            if [ -n "$ACTUAL_SHA" ]; then
                if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
                    echo "Error: Checksum verification failed for ${ASSET_NAME}!" >&2
                    echo "  Expected: $EXPECTED_SHA" >&2
                    echo "  Actual:   $ACTUAL_SHA" >&2
                    exit 1
                fi
                echo "Checksum verified: $ACTUAL_SHA"
            fi
        fi
    fi

    # Extract archive
    echo "==> Extracting $ASSET_NAME..."
    tar -xzf "$TMP_DIR/$ASSET_NAME" -C "$TMP_DIR"
    DOWNLOADED_BIN="$(find "$TMP_DIR" -type f -name wspe | head -n 1)"
    if [ -z "$DOWNLOADED_BIN" ] || [ ! -f "$DOWNLOADED_BIN" ]; then
        echo "Error: Could not locate 'wspe' binary in extracted archive." >&2
        exit 1
    fi
    chmod +x "$DOWNLOADED_BIN"
    SOURCE_BIN="$DOWNLOADED_BIN"
fi

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

UNINSTALL_CMD="$0 --uninstall"
case "$0" in
    sh|-sh|bash|zsh)
        UNINSTALL_CMD="curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | sh -s -- --uninstall"
        ;;
esac

echo ""
echo "================================================================="
echo "                  wspe Installation Complete                     "
echo "================================================================="
echo "Binary:        $TARGET_BIN"
echo "LaunchAgent:   $PLIST_PATH"
echo "Logs:          /tmp/wspe.log"
echo ""

case ":$PATH:" in
    *:"$(dirname "$TARGET_BIN")":*) ;;
    *)
        echo "PATH Notice:"
        echo "  '$(dirname "$TARGET_BIN")' is not in your current PATH."
        echo "  Consider adding it to your shell configuration (e.g. ~/.zshrc):"
        echo "      export PATH=\"$(dirname "$TARGET_BIN"):\$PATH\""
        echo ""
        ;;
esac

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
echo "  Uninstall:     $UNINSTALL_CMD"
echo "================================================================="
