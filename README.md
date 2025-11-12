# Dell-Update-Automation

Comprehensive Dell update management using Dell Command Update CLI with Apache/MariaDB reporting integration.

## Features
- ✅ Validates Dell hardware and prerequisites
- ✅ Scans for available updates
- ✅ Maintains Excel catalog of updates
- ✅ Installs updates with configurable reboot options
- ✅ Provides verbose logging and progress reporting
- ✅ Centralized reporting to Apache web server with MariaDB backend

---

## 📋 Changelog

### Branch: `beta-v2`

#### Configuration Files - v0.2

##### **settings.json - v0.2**
Configuration placeholders that require your environment-specific values:

| Placeholder | Description | Occurrences |
|------------|-------------|-------------|
| `YOUR_SERVER_IP_HERE` | Apache/MariaDB server IP address | 2 places |
| `YOUR_DATABASE_NAME_HERE` | MariaDB database name | 1 place |
| `YOUR_DB_USERNAME_HERE` | Database username | 1 place |
| `YOUR_DB_PASSWORD_HERE` | Database password | 1 place |
| `YOUR_API_KEY_HERE` | API authentication key (optional) | 1 place |

##### **Generate-Report.ps1 - v0.2**
Script dependencies that require configuration:

| Placeholder | Description |
|------------|-------------|
| `C:\Path\To\MySql.Data.dll` | Full path to MySQL .NET Connector library |

**Prerequisites:**
- Download MySQL .NET Connector from [MySQL official site](https://dev.mysql.com/downloads/connector/net/)
- Install or extract the connector DLL
- Update the path in the script

##### **ConfigManager.psm1 - v0.2**
Module reads configuration from `settings.json`. No direct placeholders required in this file.

**Database Configuration (MariaDB):**
- Server IP address
- Database name
- Database credentials (username/password)
- Table name: `update_reports` (default, customizable)

**Web Server Configuration (Apache API):**
- API endpoint URL
- API authentication key
- Default endpoint path: `/api/update-report.php` (customizable)
- Request timeout: 30 seconds (customizable)

---

## 🚀 Quick Setup

1. **Configure settings.json:**
   ```bash
   cd src/config
   # Edit settings.json with your environment values
   ```

2. **Install MySQL .NET Connector:**
   - Download from MySQL website
   - Update path in Generate-Report.ps1

3. **Setup MariaDB:**
   ```sql
   CREATE TABLE update_reports (
       id INT AUTO_INCREMENT PRIMARY KEY,
       update_id VARCHAR(255),
       title VARCHAR(500),
       status VARCHAR(50),
       date DATETIME,
       computer_name VARCHAR(255),
       generated_at DATETIME,
       INDEX idx_computer (computer_name),
       INDEX idx_generated (generated_at)
   );
   ```

4. **Deploy Apache API endpoint:**
   - Place PHP script at `/api/update-report.php`
   - Configure authentication if using API keys

---

## 📝 Version History

| Version | Component | Changes |
|---------|-----------|---------|
| v0.2 | settings.json | Added database and web server configuration sections |
| v0.2 | Generate-Report.ps1 | Added database and web API reporting functionality |
| v0.2 | ConfigManager.psm1 | Added `Get-DatabaseConfig` and `Get-WebServerConfig` functions |

---

## 🔧 Support

For issues or questions, please open an issue on the GitHub repository.