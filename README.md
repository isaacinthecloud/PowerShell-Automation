# Enterprise System Manager

A PowerShell automation solution for enterprise IT operations, demonstrating Active Directory user provisioning and SQL Server data management in a unified workflow.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows%20Server-0078D6?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)

## 🎯 Project Overview

This project automates two common enterprise IT tasks:

1. **Active Directory User Provisioning** - Bulk creation of Finance department users from CSV data
2. **SQL Server Client Data Import** - Automated database setup and client contact data ingestion

Built to demonstrate proficiency in:
- PowerShell scripting and automation
- Active Directory management
- SQL Server database operations
- Enterprise logging and error handling
- CSV data processing and validation

---

## ✨ Features

### Robust Logging System
- Multi-level logging (DEBUG, INFO, WARN, ERROR, FATAL)
- Timestamped entries with unique execution ID tracking
- Dual output: persistent log file + color-coded console
- Full PowerShell transcript capture for audit trails

### Active Directory Integration
- Automated OU creation and management
- Bulk user provisioning from CSV input
- Input validation with phone number and field format checking
- Detailed success/failure tracking per user

### SQL Server Operations
- Idempotent database and table creation (safe to re-run)
- Bulk data import with field validation
- Transaction-safe record insertion
- Comprehensive error handling

### Comprehensive Reporting
| Output File | Description |
|-------------|-------------|
| `AdResults.csv` | Successfully created AD users |
| `SqlResults.csv` | Successfully imported SQL records |
| `Summary.json` | Machine-readable execution summary |
| `ErrorDetails_[date].txt` | Consolidated error/warning report |
| `ScriptLog_[date].txt` | Complete operational log |
| `Transcript_[datetime].txt` | Full PowerShell session capture |

---

## 📋 Prerequisites

### Required Software
- Windows Server 2016+ or Windows 10/11 with RSAT tools
- PowerShell 5.1 or higher
- Active Directory PowerShell Module
- SQL Server (tested with SQL Server Express)
- SqlServer PowerShell Module

### Required Permissions
- Domain Admin rights (for AD user creation)
- SQL Server database creation rights
- Local Administrator (recommended)

### Domain Configuration
- **Domain:** `isaacinthecloud.com`
- **Target OU:** Finance (created automatically by script)

## 💻 Usage

### Basic Execution

```
Run the script with elevated privileges (Run as Administrator)
.\EnterpriseSystemManager.ps1
```

### Expected Input Files

**FinancePersonnel.csv** - Active Directory users to create:
```csv
First_Name,Last_Name,samAccount,PostalCode,MobilePhone,OfficePhone
John,Doe,jdoe,12345,5551234567,5559876543
```

**NewClientData.csv** - Client contacts to import:
```csv
first_name,last_name,city,county,zip,officePhone,mobilePhone
Jane,Smith,Springfield,Sangamon,62701,2175551234,2175555678
```

---

## 📊 Sample Output

```
2024-01-20 14:32:15 | INFO  | EnterpriseSystemManager.ps1 | Script execution started
2024-01-20 14:32:15 | INFO  | EnterpriseSystemManager.ps1 | ActiveDirectory module found
2024-01-20 14:32:15 | INFO  | EnterpriseSystemManager.ps1 | SqlServer module found
2024-01-20 14:32:16 | INFO  | EnterpriseSystemManager.ps1 | Connected to correct domain: isaacinthecloud.com
2024-01-20 14:32:18 | INFO  | EnterpriseSystemManager.ps1 | Finance OU created at OU=Finance,DC=isaacinthecloud,DC=com
2024-01-20 14:32:19 | INFO  | EnterpriseSystemManager.ps1 | Created AD user: John Doe (jdoe)
2024-01-20 14:32:20 | INFO  | EnterpriseSystemManager.ps1 | AD import completed - Processed: 5, Created: 5, Failed: 0
============================================================
EXECUTION SUMMARY
============================================================
Total execution time (seconds): 12.45
AD - Processed: 5 | Created: 5 | Failed: 0
SQL - Processed: 10 | Imported: 10 | Failed: 0
Total Errors: 0
Total Warnings: 0
```

---

## 🏗️ Architecture

```
EnterpriseSystemManager.ps1
│
├── Logger (Custom PSObject)
│   ├── Debug()   → Verbose diagnostics (gray)
│   ├── Info()    → Standard operations (green)
│   ├── Warn()    → Non-fatal issues (yellow)
│   ├── Error()   → Operation failures (red)
│   └── Fatal()   → Critical errors (magenta)
│
├── Validation Functions
│   ├── Test-Prerequisites()     → Module/file/domain checks
│   ├── Test-EmailFormat()       → Email regex validation
│   ├── Test-PhoneFormat()       → Phone number validation
│   └── Test-RequiredFields()    → CSV field validation
│
├── Import Functions
│   ├── Import-ADUsers()         → AD provisioning workflow
│   └── Import-SQLClients()      → SQL data import workflow
│
└── Main Execution
    ├── Environment logging
    ├── Prerequisite validation
    ├── AD operations (OU + users)
    ├── SQL operations (DB + table + data)
    └── Results file generation
```

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| Custom logger object | Consistent formatting, dual output (file + console), color-coded severity, execution ID for log correlation |
| Phone/email validation | Demonstrates input sanitization best practices; warnings don't block operations |
| Idempotent DB operations | Script can run multiple times safely; supports iterative testing |
| Transcript capture | Full audit trail for compliance and debugging |

---

## 🔧 Customization

### Changing the Target Domain
Edit the domain validation in `Test-Prerequisites()`:
```powershell
if ($domain.DNSRoot -ne "yourdomain.com") {
    # Update to match your domain
}
```

### Modifying SQL Instance
Update the `$SqlInstance` variable:
```powershell
$SqlInstance = 'yourserver\SQLINSTANCE'
```

### Adjusting Default Password
Edit the password in `Import-ADUsers()`:
```powershell
$securePassword = ConvertTo-SecureString "YourComplexPassword!" -AsPlainText -Force
```

## 📝 Known Limitations

- Designed for single-domain AD environments
- Assumes SQL Server Express on localhost (configurable)
- Phone validation supports 10-digit US format only
- No duplicate user checking (AD will error if user already exists)
- Requires Finance OU to be deletable for clean re-runs

---

## 📚 Skills Demonstrated

| Category | Technologies/Concepts |
|----------|----------------------|
| **Scripting** | PowerShell 5.1+, functions, parameters, error handling |
| **Active Directory** | New-ADUser, OU management, domain connectivity |
| **SQL Server** | Database creation, table schemas, Invoke-Sqlcmd |
| **Data Processing** | CSV import, input validation, format checking |
| **Logging** | Structured logging, audit trails, execution tracking |
| **Best Practices** | Idempotency, defensive programming, comprehensive reporting |

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Isaac Suazo**
- GitHub: [@isaacinthecloud](https://github.com/isaacinthecloud)

---