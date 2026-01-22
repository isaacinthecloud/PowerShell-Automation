<#
.SYNOPSIS
    EnterpriseSystemManager.ps1 provisions Finance users in Active Directory 
    from a CSV and imports new client contact data into SQL Server from a CSV.

.DESCRIPTION
    This script demonstrates common enterprise automation patterns:
    - Structured logging to a daily log file + console
    - Console transcript capture for auditing
    - Input validation and defensive error handling
    - Active Directory user provisioning from CSV
    - SQL Server database/table creation and data import from CSV
    - Machine-readable run summary (Summary.json) plus human-readable error report

.INPUTS
    - FinancePersonnel.csv (columns: First_Name, Last_Name, samAccount, PostalCode, MobilePhone, OfficePhone)
    - NewClientData.csv (columns: first_name, last_name, city, county, zip, officePhone, mobilePhone)

.OUTPUTS
    - AdResults.csv
    - SqlResults.csv
    - Summary.json
    - ScriptLog_yyyy-MM-dd.txt
    - Transcript_yyyy-MM-dd_HHmmss.txt
    - ErrorDetails_yyyy-MM-dd.txt (only if warnings/errors occur)

.NOTES
    Author:  Isaac Suazo
    Version: 2.0
    GitHub:  https://github.com/isaacinthecloud/PowerShell-Automation
#>


#region Logger
# Creates a lightweight logger object used throughout the script for consistent, timestamped logging.
# Each log entry includes: timestamp, severity level, script name, and message.
# Output goes to both a daily log file and the console with color-coded severity.

$global:Logger = [PSCustomObject]@{
    LogFile     = Join-Path $PSScriptRoot ("ScriptLog_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd'))
    ScriptName  = "EnterpriseSystemManager.ps1"
    ExecutionID = [guid]::NewGuid().ToString()
}

# DEBUG: Verbose diagnostic logging (gray console output)
# Use for detailed troubleshooting information not needed in normal operations
$global:Logger | Add-Member -MemberType ScriptMethod -Name Debug -Value {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | DEBUG | $($this.ScriptName) | $Message"
    $entry | Out-File -FilePath $this.LogFile -Append -Encoding utf8
    Write-Host $entry -ForegroundColor Gray
}

# INFO: Standard operational messages (green console output)
# Use for normal progress updates and successful operations
$global:Logger | Add-Member -MemberType ScriptMethod -Name Info -Value {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | INFO  | $($this.ScriptName) | $Message"
    $entry | Out-File -FilePath $this.LogFile -Append -Encoding utf8
    Write-Host $entry -ForegroundColor Green
}

# WARN: Non-fatal issues (yellow console output)
# Use when something unexpected happens but processing can continue
$global:Logger | Add-Member -MemberType ScriptMethod -Name Warn -Value {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | WARN  | $($this.ScriptName) | $Message"
    $entry | Out-File -FilePath $this.LogFile -Append -Encoding utf8
    Write-Host $entry -ForegroundColor Yellow
}

# ERROR: Failures for a specific operation (red console output)
# Use when an individual item fails but script can continue with other items
$global:Logger | Add-Member -MemberType ScriptMethod -Name Error -Value {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | ERROR | $($this.ScriptName) | $Message"
    $entry | Out-File -FilePath $this.LogFile -Append -Encoding utf8
    Write-Host $entry -ForegroundColor Red
}

# FATAL: Critical run-stopping failures (magenta console output)
# Use when the script cannot continue and must exit
$global:Logger | Add-Member -MemberType ScriptMethod -Name Fatal -Value {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp | FATAL | $($this.ScriptName) | $Message"
    $entry | Out-File -FilePath $this.LogFile -Append -Encoding utf8
    Write-Host $entry -ForegroundColor Magenta
}
#endregion Logger


#region Tracking and configuration
# Script-scoped counters and collections used to build results files and the final Summary.json report.
# These track successes, failures, and issues encountered during execution.

# Active Directory operation counters
$script:ADUsersProcessed = 0
$script:ADUsersCreated   = 0
$script:ADUsersFailed    = 0

# AD issue tracking collections
$script:ADErrors   = @()
$script:ADWarnings = @()
$script:CreatedUsers = @()

# SQL Server operation counters
$script:SQLRecordsProcessed = 0
$script:SQLRecordsImported  = 0
$script:SQLRecordsFailed    = 0

# SQL issue tracking collections
$script:SQLErrors   = @()
$script:SQLWarnings = @()
$script:ImportedRecords = @()

# SQL Server instance - modify this to match your environment
$SqlInstance = 'localhost\SQLEXPRESS'

# Capture start time for duration calculation
$ScriptStartTime = Get-Date
#endregion Tracking and configuration


#region Validation and import functions
# Each function has a single responsibility: prerequisites, validation, AD provisioning, or SQL import.
# This separation makes the code testable and maintainable.

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Verifies all required modules, files, and connectivity before main execution.
    .DESCRIPTION
        Checks for AD and SQL modules, validates domain connectivity,
        and confirms input CSV files exist. Returns $true if all prerequisites met.
    #>
    
    $global:Logger.Info("Checking prerequisites...")
    $prereqMet = $true

    # Check for Active Directory PowerShell module
    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    if (-not $adModule) {
        $global:Logger.Error("ActiveDirectory module not found")
        $prereqMet = $false
    }
    else {
        $global:Logger.Info("ActiveDirectory module found")
    }

    # Check for SQL Server PowerShell module
    $sqlModule = Get-Module -ListAvailable -Name SqlServer
    if (-not $sqlModule) {
        $global:Logger.Error("SqlServer module not found")
        $prereqMet = $false
    }
    else {
        $global:Logger.Info("SqlServer module found")
    }

    # Check for Administrator privileges (warn only - some operations may still work)
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        $global:Logger.Warn("Script not running as Administrator - some operations may fail")
    }
    else {
        $global:Logger.Info("Running with Administrator privileges")
    }

    # Validate domain connectivity and correct domain name
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -ErrorAction Stop

        if ($domain.DNSRoot -ne "isaacinthecloud.com") {
            $global:Logger.Error("Connected to wrong domain: $($domain.DNSRoot) (expected isaacinthecloud.com)")
            $prereqMet = $false
        }
        else {
            $global:Logger.Info("Connected to correct domain: $($domain.DNSRoot)")
        }
    }
    catch {
        $global:Logger.Error("Failed to validate domain connectivity: $($_)")
        $prereqMet = $false
    }

    # Validate required input CSV files exist
    $requiredFiles = @(
        (Join-Path $PSScriptRoot "FinancePersonnel.csv"),
        (Join-Path $PSScriptRoot "NewClientData.csv")
    )

    foreach ($file in $requiredFiles) {
        $leaf = Split-Path $file -Leaf
        if (-not (Test-Path -Path $file)) {
            $global:Logger.Error("Required file not found: $leaf")
            $prereqMet = $false
        }
        else {
            $global:Logger.Info("Required file found: $leaf")
        }
    }

    return $prereqMet
}


function Test-EmailFormat {
    <#
    .SYNOPSIS
        Validates that a string matches basic email format.
    .PARAMETER Email
        The email address string to validate.
    .OUTPUTS
        [bool] True if format is valid, False otherwise.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email
    )

    $pattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    return ($Email -match $pattern)
}


function Test-PhoneFormat {
    <#
    .SYNOPSIS
        Validates phone numbers are in expected 10-digit US format.
    .DESCRIPTION
        Strips all non-digit characters and checks for exactly 10 digits.
        Accepts various input formats: (555) 555-5555, 555-555-5555, 5555555555
    .PARAMETER Phone
        The phone number string to validate.
    .OUTPUTS
        [bool] True if valid 10-digit number, False otherwise.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Phone
    )

    # Remove all non-digit characters for consistent validation
    $digits = ($Phone -replace '[^\d]', '')

    # US phone numbers should be exactly 10 digits
    if ($digits.Length -eq 10) {
        return $true
    }

    return $false
}


function Test-RequiredFields {
    <#
    .SYNOPSIS
        Checks that a CSV record contains all required fields with values.
    .PARAMETER Record
        The PSObject representing a CSV row.
    .PARAMETER RequiredFields
        Array of field names that must be present and non-empty.
    .OUTPUTS
        [string[]] Array of missing field names (empty if all present).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Record,

        [Parameter(Mandatory=$true)]
        [string[]]$RequiredFields
    )

    $missing = @()

    foreach ($field in $RequiredFields) {
        # Check if the property exists on the record
        if (-not $Record.PSObject.Properties.Name -contains $field) {
            $missing += $field
            continue
        }

        # Check if the value is empty or whitespace
        $val = $Record.$field
        if ([string]::IsNullOrWhiteSpace([string]$val)) {
            $missing += $field
        }
    }

    return $missing
}


function Import-ADUsers {
    <#
    .SYNOPSIS
        Reads FinancePersonnel.csv and creates AD users in the Finance OU.
    .DESCRIPTION
        Iterates through CSV records, validates required fields and phone formats,
        then creates users with New-ADUser. Tracks successes and failures for reporting.
    .PARAMETER CsvPath
        Full path to the FinancePersonnel.csv file.
    .PARAMETER OUPath
        Distinguished name of the target OU (e.g., "OU=Finance,DC=isaacinthecloud,DC=com")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,

        [Parameter(Mandatory=$true)]
        [string]$OUPath
    )

    $global:Logger.Info("Starting AD user import from $CsvPath")

    # Load all users from CSV
    try {
        $users = Import-Csv -Path $CsvPath -ErrorAction Stop
        $global:Logger.Info("Loaded $($users.Count) users from CSV")
    }
    catch {
        $global:Logger.Error("Failed to read CSV file: $($_)")
        return
    }

    foreach ($user in $users) {
        $script:ADUsersProcessed++

        # Validate required fields - skip user if missing
        $required = @("First_Name","Last_Name","samAccount")
        $missing = Test-RequiredFields -Record $user -RequiredFields $required

        if ($missing.Count -gt 0) {
            $msg = "Missing required fields for user record: $($missing -join ', ')"
            $global:Logger.Warn($msg)
            $script:ADWarnings += $msg
            $script:ADUsersFailed++
            continue
        }

        # Validate phone formats - warn but continue if invalid
        if ($user.MobilePhone -and -not (Test-PhoneFormat -Phone $user.MobilePhone)) {
            $msg = "Invalid MobilePhone format for $($user.samAccount): $($user.MobilePhone)"
            $global:Logger.Warn($msg)
            $script:ADWarnings += $msg
        }

        if ($user.OfficePhone -and -not (Test-PhoneFormat -Phone $user.OfficePhone)) {
            $msg = "Invalid OfficePhone format for $($user.samAccount): $($user.OfficePhone)"
            $global:Logger.Warn($msg)
            $script:ADWarnings += $msg
        }

        # Build user display name and UPN
        $displayName = "$($user.First_Name) $($user.Last_Name)"
        $upn = "$($user.samAccount)@isaacinthecloud.com"

        try {
            # Create secure password (USE PROPER CREDENTIAL MANAGEMENT IN PRODUCTION)
            $securePassword = ConvertTo-SecureString "TempP@ss2026!" -AsPlainText -Force

            # Create the AD user
            New-ADUser `
                -Name $displayName `
                -GivenName $user.First_Name `
                -Surname $user.Last_Name `
                -SamAccountName $user.samAccount `
                -UserPrincipalName $upn `
                -Path $OUPath `
                -AccountPassword $securePassword `
                -Enabled $true `
                -ChangePasswordAtLogon $true `
                -ErrorAction Stop

            $global:Logger.Info("Created AD user: $displayName ($($user.samAccount))")
            $script:ADUsersCreated++

            # Store original record for AdResults.csv
            $script:CreatedUsers += $user
        }
        catch {
            $errMsg = "Failed to create AD user $displayName ($($user.samAccount)): $($_)"
            $global:Logger.Error($errMsg)
            $script:ADErrors += $errMsg
            $script:ADUsersFailed++
        }
    }

    $global:Logger.Info("AD import completed - Processed: $script:ADUsersProcessed, Created: $script:ADUsersCreated, Failed: $script:ADUsersFailed")
}


function Import-SQLClients {
    <#
    .SYNOPSIS
        Creates database/table if needed and imports client data from CSV to SQL Server.
    .DESCRIPTION
        Ensures ClientDB_A database and Client_A_Contacts table exist (idempotent),
        then inserts each CSV record. Tracks successes and failures for reporting.
    .PARAMETER CsvPath
        Full path to the NewClientData.csv file.
    .PARAMETER SqlInstance
        SQL Server instance name (e.g., "localhost\SQLEXPRESS")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,

        [Parameter(Mandatory=$true)]
        [string]$SqlInstance
    )

    $global:Logger.Info("Starting SQL import from $CsvPath")

    # Load all clients from CSV
    try {
        $clients = Import-Csv -Path $CsvPath -ErrorAction Stop
        $global:Logger.Info("Loaded $($clients.Count) client records from CSV")
    }
    catch {
        $global:Logger.Error("Failed to read CSV file: $($_)")
        return
    }

    $dbName = "ClientDB_A"

    # Ensure database exists (idempotent - safe to run multiple times)
    try {
        $dbExistsQuery = "SELECT DB_ID('$dbName') AS DbId;"
        $dbResult = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $dbExistsQuery -ErrorAction Stop

        if (-not $dbResult.DbId) {
            $global:Logger.Warn("$dbName does not exist - creating database")
            Invoke-Sqlcmd -ServerInstance $SqlInstance -Query "CREATE DATABASE [$dbName];" -ErrorAction Stop | Out-Null
            $global:Logger.Info("$dbName created successfully")
        }
        else {
            $global:Logger.Info("$dbName already exists")
        }

        # Ensure table exists (idempotent - only creates if missing)
        $createTableQuery = @"
USE [$dbName];
IF OBJECT_ID('dbo.Client_A_Contacts','U') IS NULL
BEGIN
    CREATE TABLE dbo.Client_A_Contacts (
        client_id     INT IDENTITY(1,1) NOT NULL,
        first_name    NVARCHAR(50) NOT NULL,
        last_name     NVARCHAR(50) NOT NULL,
        city          NVARCHAR(50) NOT NULL,
        county        NVARCHAR(50) NULL,
        zip           NVARCHAR(10) NULL,
        officePhone   NVARCHAR(20) NULL,
        mobilePhone   NVARCHAR(20) NULL,
        created_date  DATETIME NOT NULL CONSTRAINT [DF_Client_A_Contacts_created_date] DEFAULT (GETDATE()),
        CONSTRAINT [PK_Client_A_Contacts] PRIMARY KEY CLUSTERED (client_id ASC)
    );
END
"@

        Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $createTableQuery -ErrorAction Stop | Out-Null
        $global:Logger.Info("Verified table dbo.Client_A_Contacts exists")
    }
    catch {
        $errMsg = "Failed to validate/create SQL database/table: $($_)"
        $global:Logger.Error($errMsg)
        $script:SQLErrors += $errMsg
        return
    }

    # Insert each client record
    foreach ($client in $clients) {
        $script:SQLRecordsProcessed++

        # Validate required fields
        $required = @("first_name","last_name","city")
        $missing = Test-RequiredFields -Record $client -RequiredFields $required

        if ($missing.Count -gt 0) {
            $msg = "Missing required fields for client record: $($missing -join ', ')"
            $global:Logger.Warn($msg)
            $script:SQLWarnings += $msg
            $script:SQLRecordsFailed++
            continue
        }

        try {
            # Build and execute INSERT statement
            # Note: In production, use parameterized queries to prevent SQL injection
            $insertQuery = @"
USE [ClientDB_A];
INSERT INTO dbo.Client_A_Contacts (first_name, last_name, city, county, zip, officePhone, mobilePhone)
VALUES (N'$($client.first_name)', N'$($client.last_name)', N'$($client.city)', N'$($client.county)', N'$($client.zip)', N'$($client.officePhone)', N'$($client.mobilePhone)');
"@

            Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $insertQuery -ErrorAction Stop | Out-Null

            $script:SQLRecordsImported++
            $script:ImportedRecords += $client
        }
        catch {
            $errMsg = "Failed to import client $($client.first_name) $($client.last_name): $($_)"
            $global:Logger.Error($errMsg)
            $script:SQLRecordsFailed++
            $script:SQLErrors += $errMsg
        }
    }

    $global:Logger.Info("SQL import completed - Processed: $script:SQLRecordsProcessed, Imported: $script:SQLRecordsImported, Failed: $script:SQLRecordsFailed")
}
#endregion Validation and import functions


#region Main execution
# Orchestrates the entire run: starts transcript, logs environment, checks prerequisites,
# runs AD + SQL operations, then generates all output files.

# Start transcript for complete session capture
$transcriptPath = Join-Path $PSScriptRoot ("Transcript_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))
Start-Transcript -Path $transcriptPath -ErrorAction Stop | Out-Null

$global:Logger.Info(("=" * 60))
$global:Logger.Info("Script execution started at $ScriptStartTime")
$global:Logger.Info(("=" * 60))

# Log execution context for troubleshooting
$global:Logger.Info("Collecting system information...")

$systemInfo = @{}
$systemInfo["ComputerName"] = $env:COMPUTERNAME
$systemInfo["CurrentUser"]  = ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
$systemInfo["PowerShell"]   = $PSVersionTable.PSVersion.ToString()
$systemInfo["Timestamp"]    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

try {
    foreach ($kvp in $systemInfo.GetEnumerator()) {
        $global:Logger.Info("{0}: {1}" -f $kvp.Key, $kvp.Value)
    }
}
catch {
    $global:Logger.Warn("Unable to log full system info: $($_)")
}

# Gate on prerequisites - exit early if environment isn't ready
$prereqsOk = Test-Prerequisites
if (-not $prereqsOk) {
    $global:Logger.Fatal("Prerequisites not met - exiting script")
    Stop-Transcript | Out-Null
    exit 1
}

# ===============================
# Active Directory Operations
# ===============================
$global:Logger.Info(("=" * 60))
$global:Logger.Info("Starting Active Directory Operations")
$global:Logger.Info(("=" * 60))

try {
    $ouName   = "Finance"
    $domainDN = "DC=isaacinthecloud,DC=com"
    $ouPath   = "OU=$ouName,$domainDN"

    Import-Module ActiveDirectory -ErrorAction Stop

    # Remove existing OU for clean, repeatable runs (lab environment behavior)
    $existingOu = Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $domainDN -ErrorAction SilentlyContinue
    if ($existingOu) {
        $global:Logger.Warn("Finance OU already exists - deleting for repeatable run")
        Set-ADOrganizationalUnit -Identity $existingOu.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        Remove-ADOrganizationalUnit -Identity $existingOu.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
        $global:Logger.Info("Finance OU removed")
    }

    # Create fresh Finance OU
    New-ADOrganizationalUnit -Name $ouName -Path $domainDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop | Out-Null
    $global:Logger.Info("Finance OU created at $ouPath")

    # Import users from CSV
    $financeCsv = Join-Path $PSScriptRoot "FinancePersonnel.csv"
    Import-ADUsers -CsvPath $financeCsv -OUPath $ouPath
}
catch {
    $errMsg = "Active Directory operations failed: $($_)"
    $global:Logger.Error($errMsg)
    $script:ADErrors += $errMsg
}

# ===============================
# SQL Server Operations
# ===============================
$global:Logger.Info(("=" * 60))
$global:Logger.Info("Starting SQL Server Operations")
$global:Logger.Info(("=" * 60))

try {
    Import-Module SqlServer -ErrorAction Stop

    $clientsCsv = Join-Path $PSScriptRoot "NewClientData.csv"
    Import-SQLClients -CsvPath $clientsCsv -SqlInstance $SqlInstance
}
catch {
    $errMsg = "SQL operations failed: $($_)"
    $global:Logger.Error($errMsg)
    $script:SQLErrors += $errMsg
}

# ===============================
# Generate Output Files
# ===============================

# Write AD results (successfully created users)
$adResultsPath = Join-Path $PSScriptRoot "AdResults.csv"
if ($script:CreatedUsers.Count -gt 0) {
    $script:CreatedUsers | Export-Csv -Path $adResultsPath -NoTypeInformation -Encoding utf8
    $global:Logger.Info("Wrote $($script:CreatedUsers.Count) AD users to AdResults.csv")
}
else {
    $global:Logger.Warn("No AD users created - AdResults.csv not generated")
}

# Write SQL results (successfully imported records)
$sqlResultsPath = Join-Path $PSScriptRoot "SqlResults.csv"
if ($script:ImportedRecords.Count -gt 0) {
    $script:ImportedRecords | Export-Csv -Path $sqlResultsPath -NoTypeInformation -Encoding utf8
    $global:Logger.Info("Wrote $($script:ImportedRecords.Count) SQL records to SqlResults.csv")
}
else {
    $global:Logger.Warn("No SQL records imported - SqlResults.csv not generated")
}

# Build consolidated summary object
$AllErrors   = @($script:ADErrors + $script:SQLErrors)
$AllWarnings = @($script:ADWarnings + $script:SQLWarnings)

$stopTime = Get-Date
$durationSeconds = [math]::Round(($stopTime - $ScriptStartTime).TotalSeconds, 2)

$summary = [ordered]@{
    ExecutionID        = $global:Logger.ExecutionID
    ScriptName         = $global:Logger.ScriptName
    StartTime          = $ScriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
    StopTime           = $stopTime.ToString("yyyy-MM-dd HH:mm:ss")
    DurationSeconds    = $durationSeconds

    AD_Processed       = $script:ADUsersProcessed
    AD_Created         = $script:ADUsersCreated
    AD_Failed          = $script:ADUsersFailed

    SQL_Processed      = $script:SQLRecordsProcessed
    SQL_Imported       = $script:SQLRecordsImported
    SQL_Failed         = $script:SQLRecordsFailed

    ErrorsCount        = $AllErrors.Count
    WarningsCount      = $AllWarnings.Count
}

# Write machine-readable summary JSON
$summaryJsonPath = Join-Path $PSScriptRoot "Summary.json"
$summary | ConvertTo-Json -Depth 3 | Out-File -FilePath $summaryJsonPath -Encoding utf8
$global:Logger.Info("Summary JSON file created")

# Write human-readable error report (only if issues occurred)
if (($AllErrors.Count -gt 0) -or ($AllWarnings.Count -gt 0)) {

    $errReportPath = Join-Path $PSScriptRoot ("ErrorDetails_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd"))

    $reportLines = @()
    $reportLines += "Error/Warning Report"
    $reportLines += ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    $reportLines += ("=" * 60)
    $reportLines += ""

    if ($script:ADWarnings.Count -gt 0) {
        $reportLines += "AD WARNINGS:"
        foreach ($w in $script:ADWarnings) { $reportLines += " - $w" }
        $reportLines += ""
    }

    if ($script:ADErrors.Count -gt 0) {
        $reportLines += "AD ERRORS:"
        foreach ($e in $script:ADErrors) { $reportLines += " - $e" }
        $reportLines += ""
    }

    if ($script:SQLWarnings.Count -gt 0) {
        $reportLines += "SQL WARNINGS:"
        foreach ($w in $script:SQLWarnings) { $reportLines += " - $w" }
        $reportLines += ""
    }

    if ($script:SQLErrors.Count -gt 0) {
        $reportLines += "SQL ERRORS:"
        foreach ($e in $script:SQLErrors) { $reportLines += " - $e" }
        $reportLines += ""
    }

    $reportLines | Out-File -FilePath $errReportPath -Encoding utf8
    $global:Logger.Info("ErrorDetails created - Errors: $($AllErrors.Count), Warnings: $($AllWarnings.Count)")
}
else {
    $global:Logger.Info("No errors or warnings encountered - error details file not created")
}

# ===============================
# Final Summary Output
# ===============================
$global:Logger.Info(("=" * 60))
$global:Logger.Info("EXECUTION SUMMARY")
$global:Logger.Info(("=" * 60))

$global:Logger.Info("Total execution time (seconds): $durationSeconds")

$global:Logger.Info("AD - Processed: $script:ADUsersProcessed | Created: $script:ADUsersCreated | Failed: $script:ADUsersFailed")
$global:Logger.Info("SQL - Processed: $script:SQLRecordsProcessed | Imported: $script:SQLRecordsImported | Failed: $script:SQLRecordsFailed")

$global:Logger.Info("Total Errors: $($AllErrors.Count)")
$global:Logger.Info("Total Warnings: $($AllWarnings.Count)")

$global:Logger.Info(("=" * 60))
$global:Logger.Info("Script execution completed at $($stopTime.ToString('yyyy-MM-dd HH:mm:ss'))")

# Stop transcript capture
Stop-Transcript | Out-Null
#endregion Main execution
