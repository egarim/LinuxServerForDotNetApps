#!/bin/bash

# MySQL/MariaDB Remote Root Access Configuration Script for Ubuntu 22.04 with Virtualmin
# WARNING: This script allows root access from any host - USE ONLY IN DEVELOPMENT/TESTING!

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

print_warning "This script will configure MySQL to allow root access from ANY host!"
print_warning "This is a SECURITY RISK and should only be used in development/testing environments!"
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Operation cancelled."
    exit 0
fi

# Prompt for MySQL root password
read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo

# Detect MySQL/MariaDB installation
print_status "Detecting MySQL/MariaDB installation..."
if command -v mysql > /dev/null 2>&1; then
    MYSQL_VERSION=$(mysql --version)
    print_status "Found: $MYSQL_VERSION"
else
    print_error "MySQL/MariaDB is not installed or not in PATH"
    exit 1
fi

# Test MySQL connection
print_status "Testing MySQL connection..."
if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
    print_error "Cannot connect to MySQL with provided credentials"
    exit 1
fi

print_status "MySQL connection successful!"

# Find the correct configuration file
print_status "Locating MySQL configuration file..."
CONFIG_FILE=""
POSSIBLE_CONFIG_FILES=(
    "/etc/mysql/mariadb.conf.d/50-server.cnf"
    "/etc/mysql/mysql.conf.d/mysqld.cnf"
    "/etc/mysql/my.cnf"
    "/etc/my.cnf"
    "/etc/mysql/conf.d/mysql.cnf"
    "/etc/mysql/mariadb.cnf"
)

for file in "${POSSIBLE_CONFIG_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        CONFIG_FILE="$file"
        print_status "Found configuration file: $CONFIG_FILE"
        break
    fi
done

if [[ -z "$CONFIG_FILE" ]]; then
    print_error "Could not find MySQL configuration file"
    print_status "Available files in /etc/mysql/:"
    ls -la /etc/mysql/ 2>/dev/null || echo "Directory not found"
    exit 1
fi

# Backup current MySQL configuration
print_status "Backing up MySQL configuration..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Configure MySQL to listen on all interfaces
print_status "Configuring MySQL to listen on all interfaces..."

# For MariaDB, we need to handle this differently
if [[ "$MYSQL_VERSION" == *"MariaDB"* ]]; then
    print_status "Configuring MariaDB..."
    
    # Remove existing bind-address lines
    sed -i '/^bind-address/d' "$CONFIG_FILE"
    sed -i '/^#bind-address/d' "$CONFIG_FILE"
    
    # Add bind-address under [mysqld] section
    if grep -q "^\[mysqld\]" "$CONFIG_FILE"; then
        sed -i '/^\[mysqld\]/a bind-address = 0.0.0.0' "$CONFIG_FILE"
    elif grep -q "^\[mariadb\]" "$CONFIG_FILE"; then
        sed -i '/^\[mariadb\]/a bind-address = 0.0.0.0' "$CONFIG_FILE"
    else
        echo -e "\n[mysqld]\nbind-address = 0.0.0.0" >> "$CONFIG_FILE"
    fi
    
    # Remove skip-networking if present
    sed -i '/^skip-networking/d' "$CONFIG_FILE"
    sed -i 's/^#skip-networking/#skip-networking/' "$CONFIG_FILE"
    
else
    print_status "Configuring MySQL..."
    
    # Remove existing bind-address lines
    sed -i '/^bind-address/d' "$CONFIG_FILE"
    sed -i '/^mysqlx-bind-address/d' "$CONFIG_FILE"
    
    # Add bind-address under [mysqld] section
    if grep -q "^\[mysqld\]" "$CONFIG_FILE"; then
        sed -i '/^\[mysqld\]/a bind-address = 0.0.0.0' "$CONFIG_FILE"
    else
        echo -e "\n[mysqld]\nbind-address = 0.0.0.0" >> "$CONFIG_FILE"
    fi
fi

# Show what was configured
print_status "Configuration applied:"
grep -A 5 -B 5 "bind-address" "$CONFIG_FILE" || echo "bind-address not found in config"

# Install net-tools if netstat is needed (but we'll use ss instead)
if ! command -v ss > /dev/null 2>&1; then
    print_status "Installing net-tools for network diagnostics..."
    apt-get update -qq
    apt-get install -y net-tools
fi

# Restart MySQL service
print_status "Restarting MySQL/MariaDB service..."
if systemctl is-active --quiet mysql; then
    systemctl restart mysql
    SERVICE_NAME="mysql"
elif systemctl is-active --quiet mariadb; then
    systemctl restart mariadb
    SERVICE_NAME="mariadb"
else
    print_error "Could not determine MySQL service name"
    exit 1
fi

# Wait for MySQL to be ready
print_status "Waiting for MySQL to be ready..."
sleep 3

# Test if MySQL is running and accessible
for i in {1..10}; do
    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
        print_status "MySQL is responding (attempt $i)"
        break
    fi
    print_status "Waiting for MySQL to start... (attempt $i/10)"
    sleep 2
done

# Check if MySQL is listening on all interfaces
print_status "Checking if MySQL is listening on all interfaces..."
if command -v ss > /dev/null 2>&1; then
    MYSQL_LISTENING=$(ss -tuln | grep ":3306" || echo "not found")
    print_status "MySQL listening status: $MYSQL_LISTENING"
    
    if echo "$MYSQL_LISTENING" | grep -q "0.0.0.0:3306"; then
        print_status "✓ MySQL is listening on all interfaces (0.0.0.0:3306)"
    elif echo "$MYSQL_LISTENING" | grep -q ":3306"; then
        print_warning "MySQL is listening on port 3306 but may not be on all interfaces"
        print_status "Details: $MYSQL_LISTENING"
    else
        print_error "MySQL does not appear to be listening on port 3306"
        print_status "All listening ports:"
        ss -tuln
    fi
elif command -v netstat > /dev/null 2>&1; then
    MYSQL_LISTENING=$(netstat -tuln | grep ":3306" || echo "not found")
    print_status "MySQL listening status: $MYSQL_LISTENING"
else
    print_warning "Neither ss nor netstat available, skipping port check"
fi

# Configure MySQL user permissions
print_status "Configuring MySQL root user for remote access..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
-- Show current configuration
SELECT @@bind_address as bind_address;

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root capabilities (we'll add specific ones)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Create root user that can connect from any host
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';

-- Grant all privileges to root@%
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Show current root users
SELECT User, Host FROM mysql.user WHERE User='root';
EOF

# Configure UFW firewall
print_status "Configuring UFW firewall to allow MySQL connections..."

# Check if UFW is installed and active
if command -v ufw > /dev/null 2>&1; then
    # Enable UFW if not already enabled
    ufw --force enable
    
    # Allow MySQL port (3306) from anywhere
    ufw allow 3306/tcp
    
    # Show UFW status
    print_status "UFW firewall rules:"
    ufw status numbered
else
    print_warning "UFW is not installed."
fi

# Also configure iptables directly
print_status "Configuring iptables for MySQL access..."
# Check if rule already exists
if ! iptables -C INPUT -p tcp --dport 3306 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport 3306 -j ACCEPT
    print_status "Added iptables rule for MySQL"
else
    print_status "iptables rule already exists for MySQL"
fi

# Show current iptables rules for port 3306
print_status "Current iptables rules for port 3306:"
iptables -L INPUT -n | grep 3306 || echo "No specific rules found"

# Test the configuration locally
print_status "Testing local connection to 127.0.0.1..."
if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -e "SELECT 'Local connection successful' as Status;" 2>/dev/null; then
    print_status "✓ Local connection test successful!"
else
    print_error "✗ Local connection test failed"
fi

# Test connection to 0.0.0.0 (if possible)
print_status "Testing connection to 0.0.0.0..."
if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h 0.0.0.0 -e "SELECT 'Connection successful' as Status;" 2>/dev/null; then
    print_status "✓ Connection to 0.0.0.0 successful!"
else
    print_warning "✗ Connection to 0.0.0.0 failed (this might be normal)"
fi

# Show MySQL process information
print_status "MySQL process information:"
ps aux | grep -E "(mysql|mariadb)" | grep -v grep

# Display connection information
print_status "Configuration completed!"
echo
echo "=============================================="
echo "MySQL Remote Access Information:"
echo "=============================================="
echo "Host: $(hostname -I | awk '{print $1}')"
echo "Port: 3306"
echo "Username: root"
echo "Password: [The password you entered]"
echo
echo "Connection examples:"
echo "  mysql -u root -p -h $(hostname -I | awk '{print $1}')"
echo "  mysql://root:password@$(hostname -I | awk '{print $1}'):3306/"
echo
echo "Configuration file: $CONFIG_FILE"
echo "Service name: $SERVICE_NAME"
echo

# Final diagnostic information
print_status "Diagnostic Information:"
echo "- MySQL/MariaDB version: $(mysql --version)"
echo "- Configuration file: $CONFIG_FILE"
echo "- Service status: $(systemctl is-active $SERVICE_NAME)"
echo "- Listening ports: $(ss -tuln | grep :3306 || echo 'none found')"

print_warning "Security Reminders:"
echo "- Root access from any host is a security risk"
echo "- Consider creating specific users with limited privileges"
echo "- Use strong passwords and consider IP restrictions"
echo "- Monitor MySQL logs for suspicious activity"
echo "- Consider using SSL/TLS for MySQL connections"

print_status "If you still can't connect remotely, check:"
echo "1. Your hosting provider's firewall settings"
echo "2. Any additional security groups or network ACLs"
echo "3. The MySQL error log: /var/log/mysql/error.log"

print_status "Script completed!"