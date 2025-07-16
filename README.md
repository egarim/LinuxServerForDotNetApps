# LinuxServerForDotNetApps
scripts to setup an ubuntu linux server to run dotnet apps


Install progress with external access

# Download the script
wget https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/refs/heads/main/setup_postgres.sh?token=GHSAT0AAAAAAC56EANKOKGRL4KNMSNSG45E2DX66JA -O setup_postgres.sh

# Make it executable
chmod +x setup_postgres.sh

# Run the script
./setup_postgres.sh

## or a single line

# curl
sudo bash -c "$(curl -fsSL 'https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/refs/heads/main/setup_postgres.sh?token=GHSAT0AAAAAAC56EANKOKGRL4KNMSNSG45E2DX66JA')"

# wget
sudo bash -c "$(wget -qO- 'https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/refs/heads/main/setup_postgres.sh?token=GHSAT0AAAAAAC56EANKOKGRL4KNMSNSG45E2DX66JA')"


# Virtualmin for webhosting

sudo sh -c "$(curl -fsSL https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh)" -- --bundle LAMP

![Server Setup](1.png)


![Run email domain lookup server ](2.png)


![Enable virus scanning with ClamAV](3.png)

![Database servers](4.png)
Select both postgress and MariaDb

![MariaDB password](5.png)
Set a password

![DNS configuration](6.png)
Skip

![System email address](7.png)
setup an email to get notifications

![All done](8.png)
Finish the configuration


![Password storage](9.png)
Store plain text

![MariaDB database size](10.png)
Keep default


![SSL key directory](10.png)
Per domain



![complete](11.png)
Done