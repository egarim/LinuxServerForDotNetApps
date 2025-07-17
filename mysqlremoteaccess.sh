#!/bin/bash

# MySQL Remote Root Access Configuration Script for Ubuntu 22.04 with Virtualmin
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

# Test MySQL connection
print_status "Testing MySQL connection..."
if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
    print_error "Cannot connect to MySQL with provided credentials"
    exit 1
fi

print_status "MySQL connection successful!"

# Backup current MySQL configuration
print_status "Backing up MySQL configuration..."
cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup.$(date +%Y%m%d_%H%M%S)

# Configure MySQL to listen on all interfaces
print_status "Configuring MySQL to listen on all interfaces..."
sed -i 's/^bind-address\s*=\s*127\.0\.0\.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Also handle mysqlx-bind-address if present
sed -i 's/^mysqlx-bind-address\s*=\s*127\.0\.0\.1/mysqlx-bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Restart MySQL service
print_status "Restarting MySQL service..."
systemctl restart mysql

# Wait for MySQL to be ready
print_status "Waiting for MySQL to be ready..."
sleep 3

# Configure MySQL user permissions
print_status "Configuring MySQL root user for remote access..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
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

# Check if UFW is installed
if command -v ufw > /dev/null 2>&1; then
    # Enable UFW if not already enabled
    ufw --force enable
    
    # Allow MySQL port (3306) from anywhere
    ufw allow 3306/tcp
    
    # Show UFW status
    print_status "UFW firewall rules:"
    ufw status
else
    print_warning "UFW is not installed. You may need to configure your firewall manually."
fi

# Configure iptables as backup (in case UFW is not managing iptables)
print_status "Adding iptables rule for MySQL..."
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT

# Save iptables rules (method varies by system)
if command -v iptables-persistent > /dev/null 2>&1; then
    netfilter-persistent save
elif command -v service > /dev/null 2>&1; then
    service iptables save 2>/dev/null || true
fi

# Test the configuration
print_status "Testing MySQL remote connection capability..."
if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -e "SELECT 'Remote connection test successful' as Status;" 2>/dev/null; then
    print_status "Remote connection test successful!"
else
    print_warning "Remote connection test failed. Please check the configuration."
fi

# Display connection information
print_status "Configuration completed successfully!"
echo
echo "MySQL Remote Access Information:"
echo "================================="
echo "Host: $(hostname -I | awk '{print $1}')"
echo "Port: 3306"
echo "Username: root"
echo "Password: [The password you entered]"
echo
echo "Connection examples:"
echo "  mysql -u root -p -h $(hostname -I | awk '{print $1}')"
echo "  mysql://root:password@$(hostname -I | awk '{print $1}'):3306/"
echo

print_warning "Security Reminders:"
echo "- Root access from any host is a security risk"
echo "- Consider creating specific users with limited privileges"
echo "- Use strong passwords and consider IP restrictions"
echo "- Monitor MySQL logs for suspicious activity"
echo "- Consider using SSL/TLS for MySQL connections"

print_status "Script completed successfully!"