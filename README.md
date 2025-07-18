# Linux Server For .NET Applications

A collection of scripts to set up an Ubuntu Linux server optimized for running .NET applications.

## PostgreSQL Setup

Use either of the following commands to install and configure PostgreSQL on your server:

### Using curl
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/setup_postgres.sh)"
```

### Using wget
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/setup_postgres.sh)"
```

## Virtualmin for Webhosting

Install Virtualmin with LAMP bundle using the following command:

```bash
sudo sh -c "$(curl -fsSL https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh)" -- --bundle LAMP
```

### Installation Steps

1. **Server Setup**  
   ![Server Setup](1.png)

2. **Email Domain Lookup Server**  
   ![Run email domain lookup server](2.png)

3. **Virus Scanning**  
   Enable virus scanning with ClamAV  
   ![Enable virus scanning with ClamAV](3.png)

4. **Database Servers**  
   Select both PostgreSQL and MariaDB  
   ![Database servers](4.png)

5. **MariaDB Password**  
   Set a secure password  
   ![MariaDB password](5.png)

6. **DNS Configuration**  
   Skip this step  
   ![DNS configuration](6.png)

7. **System Email Address**  
   Set up an email address to receive notifications  
   ![System email address](7.png)

8. **Complete Setup**  
   Finish the configuration  
   ![All done](8.png)

9. **Password Storage**  
   Choose to store passwords in plain text  
   ![Password storage](9.png)

10. **MariaDB Database Size**  
    Keep default settings  
    ![MariaDB database size](10.png)

11. **SSL Key Directory**  
    Select "Per domain" option  
    ![SSL key directory](12.png)

12. **Installation Complete**  
    Setup is now complete  
    ![complete](11.png)

## Remote MySQL/MariaDB Access

Configure your MySQL/MariaDB server for remote access using one of the following methods:

### Using curl
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/mysqlremoteaccess.sh)"
```

### Using wget
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/mysqlremoteaccess.sh)"
```

## Install libgdiplus for .NET Applications

Install the libgdiplus library which is required by System.Drawing in .NET applications:

### Using curl
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/install_libgdiplus.sh)"
```

### Using wget
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/egarim/LinuxServerForDotNetApps/main/install_libgdiplus.sh)"
```
