# Architecture & Design

This document explains the technical design decisions and code structure of the Enterprise System Manager script.

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    EnterpriseSystemManager.ps1                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Logger    │  │ Validation  │  │    Import Functions     │  │
│  │   Object    │  │  Functions  │  │                         │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────────────────┤  │
│  │ • Debug()   │  │ • Test-     │  │ • Import-ADUsers()      │  │
│  │ • Info()    │  │   Prereqs   │  │ • Import-SQLClients()   │  │
│  │ • Warn()    │  │ • Test-     │  │                         │  │
│  │ • Error()   │  │   Email     │  │                         │  │
│  │ • Fatal()   │  │ • Test-     │  │                         │  │
│  │             │  │   Phone     │  │                         │  │
│  │             │  │ • Test-     │  │                         │  │
│  │             │  │   Required  │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      Main Execution Block                       │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌─────────────┐   │
│  │  Prereq   │→ │    AD     │→ │   SQL     │→ │   Report    │   │
│  │   Check   │  │   Import  │  │   Import  │  │ Generation  │   │
│  └───────────┘  └───────────┘  └───────────┘  └─────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         │                │               │              │
         ▼                ▼               ▼              ▼
    ┌─────────┐     ┌──────────┐   ┌──────────┐   ┌──────────┐
    │ Console │     │ Finance  │   │ ClientDB │   │  Output  │
    │   Log   │     │   OU     │   │    _A    │   │  Files   │
    └─────────┘     └──────────┘   └──────────┘   └──────────┘
```

---

## Code Organization

The script is organized into logical regions using PowerShell's `#region` directives:

| Region | Purpose |
|--------|---------|
| `Logger` | Custom logging object with severity-based methods |
| `Tracking and configuration` | Script-scoped counters and settings |
| `Validation and import functions` | Reusable functions for data validation and import |
| `Main execution` | Orchestration logic that ties everything together |

---

## Component Deep Dive

### 1. Logger Object

**Why a custom logger instead of Write-Host/Write-Output?**

| Approach | Pros | Cons |
|----------|------|------|
| Write-Host | Simple, built-in | No file output, hard to filter |
| Write-Output | Pipeline-friendly | Mixes with command output |
| Custom Logger | Consistent format, dual output, severity levels | Slightly more complex |

**Implementation:**
```powershell
$global:Logger = [PSCustomObject]@{
    LogFile     = Join-Path $PSScriptRoot ("ScriptLog_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd'))
    ScriptName  = "EnterpriseSystemManager.ps1"
    ExecutionID = [guid]::NewGuid().ToString()
}
```

The logger uses `Add-Member` with `ScriptMethod` to add callable methods to the object. Each method:
1. Formats a timestamp
2. Writes to the log file
3. Writes to the console with appropriate color

**Design Decision: ExecutionID**

Each run generates a unique GUID. This allows you to correlate log entries across multiple files (log, transcript, error report) for a single execution.

---

### 2. Validation Functions

#### Test-Prerequisites()

**Purpose:** Fail fast if the environment isn't ready.

**Checks performed:**
1. ActiveDirectory module availability
2. SqlServer module availability
3. Administrator privileges (warning only)
4. Domain connectivity and correct domain name
5. Required input files exist

**Why warn on non-admin instead of fail?**

Some testing scenarios might work without admin rights. The script warns but continues, letting AD/SQL operations fail with more specific errors if permissions are actually insufficient.

#### Test-PhoneFormat()

**Purpose:** Validate phone numbers are in expected format.

```powershell
$digits = ($Phone -replace '[^\d]', '')
if ($digits.Length -eq 10) { return $true }
return $false
```

**Design Decision:** Strip non-digits first, then validate length. This allows flexible input formats:
- `5551234567` 
- `555-123-4567` 
- `(555) 123-4567` 

#### Test-RequiredFields()

**Purpose:** Generic field validation for any CSV record.

Returns a list of missing fields rather than just true/false. This enables detailed error messages:
```
Missing required fields for user record: First_Name, samAccount
```

---

### 3. Import Functions

#### Import-ADUsers()

**Flow:**
```
Read CSV → For each user:
    ├── Validate required fields
    ├── Validate phone formats (warn only)
    ├── Build user attributes
    ├── Create AD user
    └── Track success/failure
```

**Key Design Decisions:**

1. **Separate success/failure tracking:**
   ```powershell
   $script:ADUsersCreated++   # or
   $script:ADUsersFailed++
   ```
   This enables accurate reporting even with partial failures.

2. **Warning vs. Error for validation:**
   - Missing required field → Skip user (counted as failure)
   - Invalid phone format → Warn and continue (user still created)

3. **Default password:**
   ```powershell
   $securePassword = ConvertTo-SecureString "TempP@ss2024!" -AsPlainText -Force
   ```
   In a lab environment, this is acceptable. Production scripts should use secure credential management (Azure Key Vault, etc.).

#### Import-SQLClients()

**Flow:**
```
Read CSV → Ensure DB exists → Ensure table exists → For each client:
    ├── Validate required fields
    ├── Build INSERT statement
    └── Execute and track result
```

**Key Design Decisions:**

1. **Idempotent setup:**
   ```sql
   IF OBJECT_ID('dbo.Client_A_Contacts','U') IS NULL
   BEGIN
       CREATE TABLE ...
   END
   ```
   The script can run multiple times without "object already exists" errors.

2. **String interpolation for SQL:**
   The current implementation uses string interpolation:
   ```powershell
   "N'$($client.first_name)'"
   ```

---

### 4. Main Execution Block

**Orchestration Pattern:**

```powershell
# 1. Initialize (transcript, logging)
Start-Transcript ...
$global:Logger.Info("Script execution started")

# 2. Gate on prerequisites
$prereqsOk = Test-Prerequisites
if (-not $prereqsOk) {
    $global:Logger.Fatal("Prerequisites not met")
    exit 1
}

# 3. Execute operations (wrapped in try/catch)
try {
    # AD operations
} catch {
    # Handle gracefully, continue to SQL
}

try {
    # SQL operations
} catch {
    # Handle gracefully, continue to reporting
}

# 4. Generate reports (always runs)
# ... create CSV, JSON, error files ...

# 5. Cleanup
Stop-Transcript
```

**Why continue after AD failure?**

The script is designed to be resilient. If AD operations fail completely, SQL operations might still succeed. The summary report captures what worked and what didn't, giving the operator full visibility.

---

## Data Flow

```
FinancePersonnel.csv                    NewClientData.csv
        │                                       │
        ▼                                       ▼
┌───────────────┐                       ┌───────────────┐
│ Import-ADUsers│                       │Import-SQLClients│
├───────────────┤                       ├───────────────┤
│ Validate      │                       │ Validate      │
│ Transform     │                       │ Transform     │
│ Create        │                       │ Insert        │
└───────┬───────┘                       └───────┬───────┘
        │                                       │
        ▼                                       ▼
┌───────────────┐                       ┌───────────────┐
│ Active        │                       │ ClientDB_A    │
│ Directory     │                       │ SQL Database  │
│ (Finance OU)  │                       │               │
└───────────────┘                       └───────────────┘
        │                                       │
        └───────────────┬───────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  Output Files   │
              ├─────────────────┤
              │ • AdResults.csv │
              │ • SqlResults.csv│
              │ • Summary.json  │
              │ • Log files     │
              └─────────────────┘
```

---

## Error Handling Strategy

| Scenario | Handling | Continues? |
|----------|----------|------------|
| Module not found | FATAL, exit | No |
| Wrong domain | FATAL, exit | No |
| CSV file missing | FATAL, exit | No |
| User missing required field | WARN, skip user | Yes |
| Invalid phone format | WARN, create anyway | Yes |
| AD user creation fails | ERROR, skip user | Yes |
| SQL record insert fails | ERROR, skip record | Yes |
| Entire AD block fails | ERROR, continue to SQL | Yes |
| Entire SQL block fails | ERROR, continue to reporting | Yes |

---

## Extensibility Points

### Adding New Validation Rules

1. Create a new `Test-*` function following the existing pattern
2. Call it from the import function
3. Decide: warning (continue) or error (skip)?

### Adding New Import Sources

The pattern is established:
1. Create `Import-NewSource()` function
2. Add tracking variables (`$script:NewSourceProcessed`, etc.)
3. Add to main execution block
4. Add to output file generation

### Supporting Additional Domains

Modify `Test-Prerequisites()` to accept domain as parameter:
```powershell
function Test-Prerequisites {
    param(
        [string]$ExpectedDomain = "isaacinthecloud.com"
    )
    ...
}
```

---

## Security Considerations

| Area | Current State | Production Recommendation |
|------|---------------|---------------------------|
| Passwords | Hardcoded default | Azure Key Vault, DPAPI |
| SQL Queries | String interpolation | Parameterized queries |
| Credentials | Plain text in memory | SecureString throughout |
| Logging | May log PII | Implement PII scrubbing |
| File Permissions | Default NTFS | Restrict to admin only |

---

## Performance Notes

- **CSV Reading:** Entire file loaded into memory. For very large files (10K+ records), consider streaming with `Get-Content | ConvertFrom-Csv`
- **AD Operations:** Sequential user creation. For bulk operations, consider using `New-ADUser` with `-PassThru` and batch processing
- **SQL Operations:** Individual INSERT statements. For large datasets, consider bulk insert with `SqlBulkCopy`

---
