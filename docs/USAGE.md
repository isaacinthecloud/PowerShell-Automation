# Usage Guide

This guide explains how to run the Enterprise System Manager script and interpret its output.

## Quick Start

```powershell
# 1. Open PowerShell as Administrator
# 2. Navigate to the script directory
# 3. Run the script
.\EnterpriseSystemManager.ps1
```

---

## Pre-Flight Checklist

Before running the script, verify:

- [ ] PowerShell is running as Administrator
- [ ] `FinancePersonnel.csv` exists in the folder that holds the PowerShell script
- [ ] `NewClientData.csv` exists in tthe folder that holds the PowerShell script
- [ ] You can reach the domain controller
- [ ] SQL Server is running and accessible

---

## Input File Formats

### FinancePersonnel.csv

This file defines the AD users to create in the Finance OU.

| Column | Required | Description | Example |
|--------|----------|-------------|---------|
| First_Name | Yes | User's first name | John |
| Last_Name | Yes | User's last name | Doe |
| samAccount | Yes | SAM account name (login) | jdoe |
| PostalCode | No | Postal/ZIP code | 12345 |
| MobilePhone | No | Mobile phone (10 digits) | 5551234567 |
| OfficePhone | No | Office phone (10 digits) | 5559876543 |

**Example:**
```csv
First_Name,Last_Name,samAccount,PostalCode,MobilePhone,OfficePhone
John,Doe,jdoe,12345,5551234567,5559876543
Jane,Smith,jsmith,54321,5552345678,5558765432
```

### NewClientData.csv

This file defines client contacts to import into SQL Server.

| Column | Required | Description | Example |
|--------|----------|-------------|---------|
| first_name | Yes | Client's first name | Alice |
| last_name | Yes | Client's last name | Johnson |
| city | Yes | City name | Springfield |
| county | No | County name | Sangamon |
| zip | No | ZIP code | 62701 |
| officePhone | No | Office phone | 2175551234 |
| mobilePhone | No | Mobile phone | 2175555678 |

**Example:**
```csv
first_name,last_name,city,county,zip,officePhone,mobilePhone
Alice,Johnson,Springfield,Sangamon,62701,2175551234,2175555678
Bob,Williams,Chicago,Cook,60601,3125551234,3125555678
```

---

## Execution Flow

When you run the script, it performs these operations in order:

```
1. Start transcript capture
2. Log system information
3. Check prerequisites
   ├── Verify AD module
   ├── Verify SQL module
   ├── Check admin rights
   ├── Validate domain connectivity
   └── Confirm input files exist
4. Active Directory operations
   ├── Remove existing Finance OU (if present)
   ├── Create new Finance OU
   └── Import users from CSV
5. SQL Server operations
   ├── Create database (if not exists)
   ├── Create table (if not exists)
   └── Import client records from CSV
6. Generate output files
7. Write execution summary
8. Stop transcript capture
```

---

## Output Files

After successful execution, you'll find these files in the repo directory:

### AdResults.csv
Contains all successfully created AD users with their original CSV data.

### SqlResults.csv
Contains all successfully imported SQL client records.

### Summary.json
Machine-readable execution summary:
```json
{
  "ExecutionID": "abc123-...",
  "ScriptName": "EnterpriseSystemManager.ps1",
  "StartTime": "2024-01-20 14:32:15",
  "StopTime": "2024-01-20 14:32:27",
  "DurationSeconds": 12.45,
  "AD_Processed": 5,
  "AD_Created": 5,
  "AD_Failed": 0,
  "SQL_Processed": 10,
  "SQL_Imported": 10,
  "SQL_Failed": 0,
  "ErrorsCount": 0,
  "WarningsCount": 0
}
```

### ScriptLog_[date].txt
Detailed timestamped log of all operations:
```
2024-01-20 14:32:15 | INFO  | EnterpriseSystemManager.ps1 | Script execution started
2024-01-20 14:32:16 | INFO  | EnterpriseSystemManager.ps1 | ActiveDirectory module found
...
```

### Transcript_[datetime].txt
Complete PowerShell session capture including all console output.

### ErrorDetails_[date].txt
Only created if errors or warnings occurred. Contains categorized list of all issues.

---

## Understanding Log Levels

| Level | Color | Meaning |
|-------|-------|---------|
| DEBUG | Gray | Verbose diagnostic information |
| INFO | Green | Normal operational messages |
| WARN | Yellow | Non-fatal issues (processing continues) |
| ERROR | Red | Operation failures for specific items |
| FATAL | Magenta | Critical errors that stop execution |

---

## Common Scenarios

### Clean Run (No Errors)
```
============================================================
EXECUTION SUMMARY
============================================================
Total execution time (seconds): 12.45
AD - Processed: 5 | Created: 5 | Failed: 0
SQL - Processed: 10 | Imported: 10 | Failed: 0
Total Errors: 0
Total Warnings: 0
```

### Run with Validation Warnings
```
2024-01-20 14:32:19 | WARN  | Invalid MobilePhone format for jdoe: 555-CALL-ME
...
Total Warnings: 1
```
The user is still created, but the warning is logged.

### Run with Failures
```
2024-01-20 14:32:19 | ERROR | Failed to create AD user John Doe (jdoe): User already exists
...
AD - Processed: 5 | Created: 4 | Failed: 1
Total Errors: 1
```

---

## Re-Running the Script

The script is designed to be **idempotent** for SQL operations but **destructive** for AD:

- **AD**: The Finance OU is deleted and recreated on each run. This ensures a clean slate but means existing users will be removed.
- **SQL**: The database and table are created only if they don't exist. Existing records are preserved; new records are appended.

### To Start Fresh

**AD Users:**
The OU is automatically cleaned on each run.

**SQL Data:**
```sql
USE ClientDB_A;
TRUNCATE TABLE dbo.Client_A_Contacts;
```

---

## Troubleshooting

### Script exits immediately with "Prerequisites not met"
- Check the log file for specific failures
- Verify AD and SQL modules are installed
- Ensure you're on the correct domain

### "Access denied" when creating users
- Verify Domain Admin permissions
- Run PowerShell as Administrator

### SQL import fails
- Check SQL Server is running
- Verify the instance name in `$SqlInstance`
- Ensure your account has db_creator rights

### Phone validation warnings
- Format phones as 10 digits: `5551234567`
- Avoid dashes, parentheses, or spaces

---

## Next Steps

- Review [ARCHITECTURE.md](ARCHITECTURE.md) to understand the code structure
- Check `examples/` for sample CSV files
