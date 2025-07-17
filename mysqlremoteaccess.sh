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

# Prompt for MySQL root password ONCE
read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo

# Create MySQL client configuration file to avoid repeated password prompts
MYSQL_CONFIG_FILE="/tmp/mysql_client_config.cnf"
cat > "$MYSQL_CONFIG_FILE" << EOF
[client]
user=root
password=$MYSQL_ROOT_PASSWORD
EOF

# Function to run MySQL commands without password prompt
run_mysql() {
    mysql --defaults-file="$MYSQL_CONFIG_FILE" "$@"
}

# Function to cleanup temp files
cleanup() {
    rm -f "$MYSQL_CONFIG_FILE"
    rm -f /tmp/mariadb_config.sql
}

# Setup cleanup on exit
trap cleanup EXIT

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
if ! run_mysql -e "SELECT 1;" > /dev/null 2>&1; then
    print_error "Cannot connect to MySQL with provided credentials"
    exit 1
fi

print_status "MySQL connection successful!"

# Check current user configuration
print_status "Checking current user configuration..."
CURRENT_USERS=$(run_mysql -e "SELECT User, Host FROM mysql.user WHERE User='root';" 2>/dev/null)
print_status "Current root users:"
echo "$CURRENT_USERS"

# Check if root@'%' already exists
ROOT_REMOTE_EXISTS=$(run_mysql -e "SELECT COUNT(*) as count FROM mysql.user WHERE User='root' AND Host='%';" -s -N 2>/dev/null)
print_status "Root user with remote access (%) exists: $([[ $ROOT_REMOTE_EXISTS -gt 0 ]] && echo "YES" || echo "NO")"

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

# Check current bind-address
CURRENT_BIND=$(run_mysql -e "SELECT @@bind_address;" -s -N 2>/dev/null)
print_status "Current bind address: $CURRENT_BIND"

# Configure MySQL to listen on all interfaces if not already set
if [[ "$CURRENT_BIND" != "0.0.0.0" ]]; then
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
        if run_mysql -e "SELECT 1;" > /dev/null 2>&1; then
            print_status "MySQL is responding (attempt $i)"
            break
        fi
        print_status "Waiting for MySQL to start... (attempt $i/10)"
        sleep 2
    done
else
    print_status "MySQL is already configured to listen on all interfaces"
    if systemctl is-active --quiet mysql; then
        SERVICE_NAME="mysql"
    elif systemctl is-active --quiet mariadb; then
        SERVICE_NAME="mariadb"
    else
        SERVICE_NAME="mysql"
    fi
fi

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
else
    print_warning "ss command not available, skipping port check"
fi

# Configure MySQL user permissions
print_status "Configuring MySQL root user for remote access..."

# Handle MariaDB and MySQL differently for user management
if [[ "$MYSQL_VERSION" == *"MariaDB"* ]]; then
    print_status "Configuring MariaDB users..."
    
    # Create a temporary SQL file for better error handling
    cat > /tmp/mariadb_config.sql << EOF
-- Show current configuration
SELECT @@bind_address as 'Current Bind Address';

-- Show current users before changes
SELECT 'Current Users:' as Info;
SELECT User, Host FROM mysql.user WHERE User='root';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Handle root@'%' user creation/update
SET @user_exists = (SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='%');
SELECT @user_exists as 'Remote Root User Exists';

-- Drop existing root@'%' if it exists to recreate with proper permissions
DROP USER IF EXISTS 'root'@'%';

-- Create root user that can connect from any host
CREATE USER 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';

-- Grant all privileges to root@%
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Show users after changes
SELECT 'Users After Configuration:' as Info;
SELECT User, Host FROM mysql.user WHERE User='root';
EOF

    # Execute the SQL file
    if run_mysql < /tmp/mariadb_config.sql; then
        print_status "✓ MariaDB user configuration completed successfully"
    else
        print_error "Failed to configure MariaDB users"
        print_status "You may need to configure manually"
    fi
    
else
    print_status "Configuring MySQL users..."
    run_mysql <<EOF
-- Show current configuration
SELECT @@bind_address as bind_address;

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove existing remote root users
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
fi

# Configure Firewall - Check what firewall system is active
print_status "Configuring firewall to allow MySQL connections..."

# Check firewall systems
FIREWALLD_ACTIVE=$(systemctl is-active firewalld 2>/dev/null || echo "inactive")
UFW_ACTIVE=$(systemctl is-active ufw 2>/dev/null || echo "inactive")

if [[ "$FIREWALLD_ACTIVE" == "active" ]]; then
    print_status "Configuring firewalld..."
    
    # Show current firewalld configuration
    print_status "Current firewalld configuration:"
    firewall-cmd --list-all
    
    # Add MySQL service
    print_status "Adding MySQL service to firewalld..."
    firewall-cmd --permanent --add-service=mysql || true
    
    # Add MySQL port directly (backup method)
    print_status "Adding MySQL port 3306 to firewalld..."
    firewall-cmd --permanent --add-port=3306/tcp || true
    
    # Add rich rule for MySQL (comprehensive method)
    print_status "Adding rich rule for MySQL..."
    firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port="3306" accept' || true
    
    # Reload firewalld to apply changes
    print_status "Reloading firewalld configuration..."
    firewall-cmd --reload
    
    # Show final firewalld configuration
    print_status "Final firewalld configuration:"
    firewall-cmd --list-all
    
elif [[ "$UFW_ACTIVE" == "active" ]] || command -v ufw > /dev/null 2>&1; then
    print_status "Configuring UFW firewall..."
    
    # Install UFW if not present
    if ! command -v ufw > /dev/null 2>&1; then
        print_status "Installing UFW..."
        apt-get update -qq
        apt-get install -y ufw
    fi
    
    # Enable UFW if not already enabled
    ufw --force enable
    
    # Allow MySQL port (3306) from anywhere
    ufw allow 3306/tcp
    
    # Show UFW status
    print_status "UFW firewall rules:"
    ufw status numbered
    
else
    print_status "Configuring iptables directly..."
    
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
fi

# Test the configuration locally
print_status "Testing local connections..."

# Test localhost connection
if run_mysql -h localhost -e "SELECT 'Localhost connection successful' as Status;" 2>/dev/null; then
    print_status "✓ Localhost connection successful"
else
    print_warning "✗ Localhost connection failed"
fi

# Test 127.0.0.1 connection
if run_mysql -h 127.0.0.1 -e "SELECT 'Local IP connection successful' as Status;" 2>/dev/null; then
    print_status "✓ Local IP (127.0.0.1) connection successful"
else
    print_warning "✗ Local IP connection failed"
fi

# Test server IP connection
SERVER_IP=$(hostname -I | awk '{print $1}')
if run_mysql -h "$SERVER_IP" -e "SELECT 'Server IP connection successful' as Status;" 2>/dev/null; then
    print_status "✓ Server IP ($SERVER_IP) connection successful"
else
    print_warning "✗ Server IP connection failed - this may indicate a firewall issue"
fi

# Test external connectivity
print_status "Testing external port connectivity..."
if timeout 5 bash -c "</dev/tcp/$SERVER_IP/3306" 2>/dev/null; then
    print_status "✓ Port 3306 is externally accessible"
else
    print_warning "✗ Port 3306 may not be externally accessible"
fi

# Final verification of user configuration
print_status "Final user configuration verification..."
FINAL_USERS=$(run_mysql -e "SELECT User, Host FROM mysql.user WHERE User='root';" 2>/dev/null)
print_status "Final root users configuration:"
echo "$FINAL_USERS"

# Display connection information
print_status "Configuration completed!"
echo
echo "=============================================="
echo "MySQL Remote Access Information:"
echo "=============================================="
echo "Host: $SERVER_IP"
echo "Port: 3306"
echo "Username: root"
echo "Password: [The password you entered]"
echo
echo "Connection examples:"
echo "  mysql -u root -p -h $SERVER_IP"
echo "  mysql://root:password@$SERVER_IP:3306/"
echo
echo "Configuration file: $CONFIG_FILE"
echo "Service name: $SERVICE_NAME"
echo "Firewall: $([[ $FIREWALLD_ACTIVE == "active" ]] && echo "firewalld" || [[ $UFW_ACTIVE == "active" ]] && echo "ufw" || echo "iptables")"
echo

# Check if root@'%' user exists
ROOT_REMOTE_FINAL=$(run_mysql -e "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='%';" -s -N 2>/dev/null)
if [[ $ROOT_REMOTE_FINAL -gt 0 ]]; then
    print_status "✓ Remote root user (root@'%') has been created successfully"
else
    print_error "✗ Remote root user was not created - you may need to create it manually"
    print_status "Manual commands:"
    echo "  mysql -u root -p"
    echo "  CREATE USER 'root'@'%' IDENTIFIED BY 'your_password';"
    echo "  GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
    echo "  FLUSH PRIVILEGES;"
fi

print_warning "Security Reminders:"
echo "- Root access from any host is a security risk"
echo "- Consider creating specific users with limited privileges"
echo "- Use strong passwords and consider IP restrictions"
echo "- Monitor MySQL logs for suspicious activity"
echo "- Consider using SSL/TLS for MySQL connections"

print_status "Testing remote connection..."
echo "You can now test the remote connection from another machine using:"
echo "  mysql -u root -p -h $SERVER_IP"
echo "  telnet $SERVER_IP 3306"

print_status "Script completed successfully!"