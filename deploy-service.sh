#!/bin/bash
# deploy-service.sh

set -e

# Configuration file path
CONFIG_FILE="deploy-config.json"

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -c, --config FILE     Configuration file (default: deploy-config.json)"
    echo "  -l, --local DIR       Local directory to deploy"
    echo "  -h, --host HOST       Server hostname"
    echo "  -u, --user USER       SSH username"
    echo "  -s, --service NAME    Service name"
    echo "  -e, --exec PATH       Executable path (relative to remote directory)"
    echo "  -r, --remote DIR      Remote directory (default: /opt/SERVICE_NAME)"
    echo "  -d, --desc TEXT       Service description"
    echo "  --service-user USER   User to run service as (default: root)"
    echo "  --skip-test          Skip SSH connection test"
    echo "  --help               Show this help"
    echo ""
    echo "Example: $0 -l ./publish -h server.com -u root -s myapp -e myapp"
}

# Default values
REMOTE_DIR=""
SERVICE_DESC="Auto-deployed service"
SERVICE_USER="root"
SKIP_TEST=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -l|--local)
            LOCAL_DIR="$2"
            shift 2
            ;;
        -h|--host)
            SERVER_HOST="$2"
            shift 2
            ;;
        -u|--user)
            USERNAME="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -e|--exec)
            EXEC_PATH="$2"
            shift 2
            ;;
        -r|--remote)
            REMOTE_DIR="$2"
            shift 2
            ;;
        -d|--desc)
            SERVICE_DESC="$2"
            shift 2
            ;;
        --service-user)
            SERVICE_USER="$2"
            shift 2
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Load configuration from JSON if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from: $CONFIG_FILE"
    
    # Use jq if available, otherwise use basic parsing
    if command -v jq &> /dev/null; then
        [[ -z "$LOCAL_DIR" ]] && LOCAL_DIR=$(jq -r '.LocalDirectory // empty' "$CONFIG_FILE")
        [[ -z "$SERVER_HOST" ]] && SERVER_HOST=$(jq -r '.ServerHost // empty' "$CONFIG_FILE")
        [[ -z "$USERNAME" ]] && USERNAME=$(jq -r '.Username // empty' "$CONFIG_FILE")
        [[ -z "$SERVICE_NAME" ]] && SERVICE_NAME=$(jq -r '.ServiceName // empty' "$CONFIG_FILE")
        [[ -z "$EXEC_PATH" ]] && EXEC_PATH=$(jq -r '.ExecutablePath // empty' "$CONFIG_FILE")
        [[ -z "$REMOTE_DIR" ]] && REMOTE_DIR=$(jq -r '.RemoteDirectory // empty' "$CONFIG_FILE")
        [[ -z "$SERVICE_DESC" || "$SERVICE_DESC" == "Auto-deployed service" ]] && SERVICE_DESC=$(jq -r '.ServiceDescription // "Auto-deployed service"' "$CONFIG_FILE")
        [[ -z "$SERVICE_USER" || "$SERVICE_USER" == "root" ]] && SERVICE_USER=$(jq -r '.ServiceUser // "root"' "$CONFIG_FILE")
    else
        echo "Warning: jq not found, using basic JSON parsing"
        [[ -z "$LOCAL_DIR" ]] && LOCAL_DIR=$(grep -o '"LocalDirectory"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        [[ -z "$SERVER_HOST" ]] && SERVER_HOST=$(grep -o '"ServerHost"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        [[ -z "$USERNAME" ]] && USERNAME=$(grep -o '"Username"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        [[ -z "$SERVICE_NAME" ]] && SERVICE_NAME=$(grep -o '"ServiceName"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        [[ -z "$EXEC_PATH" ]] && EXEC_PATH=$(grep -o '"ExecutablePath"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        [[ -z "$REMOTE_DIR" ]] && REMOTE_DIR=$(grep -o '"RemoteDirectory"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
    echo "Configuration loaded successfully!"
else
    echo "Configuration file not found: $CONFIG_FILE"
    echo "Using command line parameters only"
fi

# Set default remote directory if not specified
[[ -z "$REMOTE_DIR" ]] && REMOTE_DIR="/opt/$SERVICE_NAME"

# Validate required parameters
MISSING_PARAMS=()
[[ -z "$LOCAL_DIR" ]] && MISSING_PARAMS+=("LOCAL_DIR")
[[ -z "$SERVER_HOST" ]] && MISSING_PARAMS+=("SERVER_HOST")
[[ -z "$USERNAME" ]] && MISSING_PARAMS+=("USERNAME")
[[ -z "$SERVICE_NAME" ]] && MISSING_PARAMS+=("SERVICE_NAME")
[[ -z "$EXEC_PATH" ]] && MISSING_PARAMS+=("EXEC_PATH")

if [[ ${#MISSING_PARAMS[@]} -gt 0 ]]; then
    echo "Error: Missing required parameters: ${MISSING_PARAMS[*]}"
    echo "Provide them via command line or in the configuration file"
    show_usage
    exit 1
fi

# Display configuration
echo ""
echo "=== Deployment Configuration ==="
echo "Local Directory: $LOCAL_DIR"
echo "Server: $SERVER_HOST"
echo "Username: $USERNAME"
echo "Service Name: $SERVICE_NAME"
echo "Executable: $EXEC_PATH"
echo "Remote Directory: $REMOTE_DIR"
echo "Service User: $SERVICE_USER"
echo "Service Description: $SERVICE_DESC"
echo "================================="
echo ""

# Convert to absolute path if relative
LOCAL_DIR=$(realpath "$LOCAL_DIR")
echo "Resolved local directory: $LOCAL_DIR"

# Test SSH connection (unless skipped)
if [[ "$SKIP_TEST" != "true" ]]; then
    echo "Testing SSH connection..."
    if ssh -o ConnectTimeout=10 -o BatchMode=no "$USERNAME@$SERVER_HOST" "echo 'SSH connection successful'"; then
        echo "SSH connection test passed!"
    else
        echo "SSH connection test failed!"
        echo "You can retry with --skip-test to bypass this check"
        exit 1
    fi
fi

# Create zip file
ZIP_FILE="/tmp/${SERVICE_NAME}.zip"
echo "Creating zip file: $ZIP_FILE"

# Check if zip is available, install if needed
if ! command -v zip &> /dev/null; then
    echo "zip command not found, installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zip
    elif command -v yum &> /dev/null; then
        sudo yum install -y zip
    elif command -v pacman &> /dev/null; then
        sudo pacman -S zip
    else
        echo "Cannot install zip automatically. Please install it manually:"
        echo "  Ubuntu/Debian: sudo apt-get install zip"
        echo "  CentOS/RHEL: sudo yum install zip"
        echo "  Arch: sudo pacman -S zip"
        exit 1
    fi
fi

cd "$LOCAL_DIR"
zip -r "$ZIP_FILE" . -x "*.git*" "*.DS_Store*" "Thumbs.db"

echo "Uploading zip file to server..."
scp "$ZIP_FILE" "$USERNAME@$SERVER_HOST:/tmp/$SERVICE_NAME.zip"

echo "Deploying service on remote server..."



# Execute deployment on remote server
ssh "$USERNAME@$SERVER_HOST" "bash -s -- '$SERVICE_NAME' '$REMOTE_DIR' '$EXEC_PATH' '$SERVICE_DESC' '$SERVICE_USER'" << 'DEPLOY_EOF'
set -e

SERVICE_NAME="$1"
REMOTE_DIR="$2"
EXEC_PATH="$3"
SERVICE_DESC="$4"
SERVICE_USER="$5"

echo "Received parameters:"
echo "  Service Name: $SERVICE_NAME"
echo "  Remote Dir: $REMOTE_DIR"
echo "  Executable: $EXEC_PATH"
echo "  Description: $SERVICE_DESC"
echo "  Service User: $SERVICE_USER"

echo "Creating directory and extracting files..."
sudo mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"
sudo unzip -o "/tmp/$SERVICE_NAME.zip"
sudo rm "/tmp/$SERVICE_NAME.zip"

echo "Setting permissions..."
sudo find . -name "*.sh" -exec chmod +x {} \;
sudo chmod +x "$EXEC_PATH" 2>/dev/null || true

echo "Stopping existing service if running..."
sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true

echo "Creating systemd service..."
sudo tee "/etc/systemd/system/$SERVICE_NAME.service" > /dev/null << SERVICE_EOF
[Unit]
Description=$SERVICE_DESC
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$REMOTE_DIR
ExecStart=$REMOTE_DIR/$EXEC_PATH
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "Reloading systemd and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo "Service $SERVICE_NAME deployed and started successfully!"
sudo systemctl status "$SERVICE_NAME" --no-pager
DEPLOY_EOF

# Clean up local zip file
rm -f "$ZIP_FILE"

echo ""
echo "Deployment completed successfully!"
echo "You can check the service status with:"
echo "  ssh $USERNAME@$SERVER_HOST 'sudo systemctl status $SERVICE_NAME'"
echo "View logs with:"
echo "  ssh $USERNAME@$SERVER_HOST 'sudo journalctl -u $SERVICE_NAME -f'"