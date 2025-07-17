#!/bin/bash

# PostgreSQL Installation and Remote Access Configuration Script
# For Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to prompt for confirmation
confirm() {
    while true; do
        read -p "$(echo -e "${YELLOW}$1 (y/n): ${NC}")" yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to show command and ask for confirmation
run_command() {
    echo -e "${BLUE}About to run: ${NC}$1"
    if confirm "Execute this command?"; then
        eval "$1"
        if [ $? -eq 0 ]; then
            print_success "Command executed successfully"
        else
            print_error "Command failed"
            exit 1
        fi
    else
        print_warning "Command skipped"
    fi
    echo
}

# Function to prompt for password with confirmation
get_password() {
    local var_name=$1
    local prompt=$2
    
    while true; do
        read -s -p "$prompt: " password
        echo
        read -s -p "Confirm password: " password2
        echo
        
        if [ "$password" = "$password2" ]; then
            eval "$var_name='$password'"
            break
        else
            print_error "Passwords don't match. Please try again."
        fi
    done
}

# Function to modify postgresql.conf
modify_postgresql_conf() {
    local config_file="/etc/postgresql/14/main/postgresql.conf"
    
    echo -e "${BLUE}About to modify: ${NC}$config_file"
    echo -e "${YELLOW}Changes to be made:${NC}"
    echo "1. Set listen_addresses = '*' (to allow remote connections)"
    echo "2. Set password_encryption = scram-sha-256 (for secure authentication)"
    echo
    
    if confirm "Apply these changes?"; then
        # Backup original file
        sudo cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created: $config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Modify listen_addresses
        if sudo grep -q "^listen_addresses" "$config_file"; then
            sudo sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$config_file"
            print_success "Modified existing listen_addresses setting"
        elif sudo grep -q "^#listen_addresses" "$config_file"; then
            sudo sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "$config_file"
            print_success "Uncommented and modified listen_addresses setting"
        else
            echo "listen_addresses = '*'" | sudo tee -a "$config_file" > /dev/null
            print_success "Added listen_addresses setting"
        fi
        
        # Modify password_encryption
        if sudo grep -q "^password_encryption" "$config_file"; then
            sudo sed -i "s/^password_encryption.*/password_encryption = scram-sha-256/" "$config_file"
            print_success "Modified existing password_encryption setting"
        elif sudo grep -q "^#password_encryption" "$config_file"; then
            sudo sed -i "s/^#password_encryption.*/password_encryption = scram-sha-256/" "$config_file"
            print_success "Uncommented and modified password_encryption setting"
        else
            echo "password_encryption = scram-sha-256" | sudo tee -a "$config_file" > /dev/null
            print_success "Added password_encryption setting"
        fi
        
        print_success "PostgreSQL configuration file modified successfully"
    else
        print_warning "PostgreSQL configuration modification skipped"
    fi
    echo
}

# Function to modify pg_hba.conf
modify_pg_hba_conf() {
    local config_file="/etc/postgresql/14/main/pg_hba.conf"
    
    echo -e "${BLUE}About to modify: ${NC}$config_file"
    echo -e "${YELLOW}Changes to be made:${NC}"
    echo "Add line: host    all             all             0.0.0.0/0               scram-sha-256"
    echo "This allows remote connections from any IP using scram-sha-256 authentication"
    echo
    
    if confirm "Apply this change?"; then
        # Backup original file
        sudo cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created: $config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Check if the line already exists
        if sudo grep -q "host.*all.*all.*0.0.0.0/0.*scram-sha-256" "$config_file"; then
            print_warning "Remote access rule already exists"
        else
            # Add the remote access line
            echo "host    all             all             0.0.0.0/0               scram-sha-256" | sudo tee -a "$config_file" > /dev/null
            print_success "Added remote access rule to pg_hba.conf"
        fi
        
        print_success "Client authentication configuration modified successfully"
    else
        print_warning "Client authentication configuration modification skipped"
    fi
    echo
}

# Function to show current configuration
show_current_config() {
    echo -e "${BLUE}Current PostgreSQL configuration:${NC}"
    echo
    echo "pg_hba.conf (authentication rules):"
    sudo cat /etc/postgresql/14/main/pg_hba.conf | grep -v "^#" | grep -v "^$"
    echo
    echo "postgresql.conf (relevant settings):"
    sudo grep -E "^(listen_addresses|password_encryption)" /etc/postgresql/14/main/postgresql.conf || echo "No explicit settings found"
    echo
}

# Main script starts here
clear
echo -e "${GREEN}PostgreSQL Installation and Remote Access Configuration Script${NC}"
echo -e "${GREEN}For Ubuntu 22.04${NC}"
echo
print_warning "This script will install PostgreSQL and configure it for remote access."
print_warning "Make sure to run this script as a user with sudo privileges."
echo

if ! confirm "Do you want to continue?"; then
    echo "Installation cancelled."
    exit 0
fi

# Step 1: Update package list
print_step "Step 1: Updating package list"
run_command "sudo apt update"

# Step 2: Install PostgreSQL
print_step "Step 2: Installing PostgreSQL"
run_command "sudo apt install -y postgresql postgresql-contrib"

# Step 3: Start and enable PostgreSQL service
print_step "Step 3: Starting and enabling PostgreSQL service"
run_command "sudo systemctl start postgresql"
run_command "sudo systemctl enable postgresql"

# Step 4: Show current configuration
print_step "Step 4: Current Configuration"
show_current_config

# Step 5: Modify PostgreSQL configuration
print_step "Step 5: Modifying PostgreSQL configuration"
modify_postgresql_conf

# Step 6: Modify client authentication
print_step "Step 6: Modifying client authentication"
modify_pg_hba_conf

# Step 7: Show updated configuration
print_step "Step 7: Updated Configuration"
show_current_config

# Step 8: Restart PostgreSQL
print_step "Step 8: Restarting PostgreSQL to apply changes"
run_command "sudo systemctl restart postgresql"

# Step 9: Set up database user and password
print_step "Step 9: Setting up database user and password"

echo "Now we'll set up the database user and password."
echo

# Get postgres user password
get_password "POSTGRES_PASSWORD" "Enter password for 'postgres' user"

# Create SQL commands
echo "We'll now connect to PostgreSQL and set the password."
echo -e "${YELLOW}SQL command to be executed:${NC}"
echo "ALTER USER postgres PASSWORD '[your_password]';"
echo

if confirm "Execute this SQL command?"; then
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"
    print_success "Password set for postgres user"
else
    print_warning "Password setup skipped"
fi

# Step 10: Create additional database user (optional)
print_step "Step 10: Create additional database user (optional)"

if confirm "Do you want to create an additional database user?"; then
    read -p "Enter username: " DB_USER
    get_password "DB_PASSWORD" "Enter password for '$DB_USER'"
    read -p "Enter database name (or press Enter for default): " DB_NAME
    
    if [ -z "$DB_NAME" ]; then
        DB_NAME="$DB_USER"
    fi
    
    echo -e "${YELLOW}SQL commands to be executed:${NC}"
    echo "CREATE USER $DB_USER WITH PASSWORD '[password]';"
    echo "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    echo "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
    echo
    
    if confirm "Execute these SQL commands?"; then
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
        print_success "User '$DB_USER' and database '$DB_NAME' created"
    fi
fi

# Step 11: Configure firewall
print_step "Step 11: Configuring firewall"

echo "We need to allow PostgreSQL port (5432) through the firewall."
echo "You can either:"
echo "1. Allow from any IP (less secure): sudo ufw allow 5432"
echo "2. Allow from specific IP range (more secure): sudo ufw allow from IP_RANGE to any port 5432"
echo

if confirm "Allow PostgreSQL port 5432 from any IP?"; then
    run_command "sudo ufw allow 5432"
else
    read -p "Enter IP range (e.g., 192.168.1.0/24): " IP_RANGE
    if [ -n "$IP_RANGE" ]; then
        run_command "sudo ufw allow from $IP_RANGE to any port 5432"
    else
        print_warning "No IP range provided, firewall rule not added"
    fi
fi

# Step 12: Verify installation
print_step "Step 12: Verifying installation"

echo "Checking PostgreSQL service status..."
run_command "sudo systemctl status postgresql --no-pager"

echo "Checking if PostgreSQL is listening on port 5432..."
# Use ss command (modern replacement for netstat) or fallback to lsof
if command -v ss >/dev/null 2>&1; then
    run_command "sudo ss -tlnp | grep 5432"
elif command -v lsof >/dev/null 2>&1; then
    run_command "sudo lsof -i :5432"
elif command -v netstat >/dev/null 2>&1; then
    run_command "sudo netstat -tlnp | grep 5432"
else
    echo -e "${YELLOW}Installing net-tools to check port status...${NC}"
    run_command "sudo apt install -y net-tools"
    run_command "sudo netstat -tlnp | grep 5432"
fi

# Step 13: Get server IP for remote connection
print_step "Step 13: Remote connection information"

echo "Getting server IP address..."
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo
print_success "PostgreSQL installation and configuration completed!"
echo
echo -e "${GREEN}=== CONFIGURATION SUMMARY ===${NC}"
echo "Files modified:"
echo "• /etc/postgresql/14/main/postgresql.conf"
echo "  - listen_addresses = '*'"
echo "  - password_encryption = scram-sha-256"
echo "• /etc/postgresql/14/main/pg_hba.conf"
echo "  - Added: host all all 0.0.0.0/0 scram-sha-256"
echo
echo -e "${GREEN}=== CONNECTION INFORMATION ===${NC}"
echo "Server IP: $SERVER_IP"
echo "Port: 5432"
echo "Database: postgres"
echo "Username: postgres"
echo "Password: [the password you set]"
echo "Authentication Method: scram-sha-256"
echo
echo -e "${GREEN}=== REMOTE CONNECTION EXAMPLES ===${NC}"
echo "Using psql:"
echo "psql -h $SERVER_IP -p 5432 -U postgres -d postgres"
echo
echo "Using DBeaver:"
echo "Host: $SERVER_IP"
echo "Port: 5432"
echo "Database: postgres"
echo "Username: postgres"
echo "Password: [your password]"
echo "Authentication: Database Native"
echo
echo -e "${GREEN}=== BACKUP FILES CREATED ===${NC}"
echo "Configuration backups were created with timestamp suffixes"
echo "Location: /etc/postgresql/14/main/*.backup.*"
echo
echo -e "${YELLOW}=== SECURITY RECOMMENDATIONS ===${NC}"
echo "• Consider restricting access to specific IP ranges instead of 0.0.0.0/0"
echo "• Use strong passwords for all database users"
echo "• Regularly update PostgreSQL and Ubuntu"
echo "• Consider setting up SSL/TLS for encrypted connections"
echo "• Monitor PostgreSQL logs: tail -f /var/log/postgresql/postgresql-14-main.log"
echo
echo -e "${GREEN}Installation completed successfully!${NC}"