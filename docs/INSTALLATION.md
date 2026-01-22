# Installation Guide

This guide walks you through setting up the environment to run the Enterprise System Manager script.

## Environment Requirements

### Operating System
- **Windows Server 2016, 2019, or 2022** (recommended for full AD functionality)
- **Windows 10/11 Pro or Enterprise** with RSAT tools (for development/testing)

### PowerShell Version
- PowerShell 5.1 or higher (included with Windows 10+)
- Check your version:
  ```powershell
  $PSVersionTable.PSVersion
  ```

---

## Step 1: Install Active Directory Module

### On Windows Server (with AD DS role)
The module is automatically available when the AD DS role is installed.

### On Windows Server (without AD DS role)
```powershell
# Install RSAT AD PowerShell tools
Install-WindowsFeature RSAT-AD-PowerShell
```

### On Windows 10/11
```powershell
# Install via Settings > Apps > Optional Features > Add a feature
# Search for "RSAT: Active Directory Domain Services and Lightweight Directory Services Tools"

# Or via PowerShell (requires admin)
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

### Verify Installation
```powershell
Get-Module -ListAvailable -Name ActiveDirectory
```

---

## Step 2: Install SQL Server Module

```powershell
# Install SqlServer module from PowerShell Gallery
Install-Module -Name SqlServer -Scope CurrentUser -Force

# If prompted about untrusted repository, type 'Y' to continue
```

### Verify Installation
```powershell
Get-Module -ListAvailable -Name SqlServer
```

---

## Step 3: SQL Server Setup

### Option A: SQL Server Express
1. Download [SQL Server Express](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
2. Run the installer and choose "Basic" installation
3. Note the instance name (default: `YOURCOMPUTER\SQLEXPRESS`)

### Option B: Use Existing SQL Server
Update the `$SqlInstance` variable in the script to point to your server:
```powershell
$SqlInstance = 'servername\instancename'
```

### Enable SQL Server Authentication (if needed)
1. Open SQL Server Management Studio
2. Right-click server → Properties → Security
3. Select "SQL Server and Windows Authentication mode"
4. Restart SQL Server service

---

## Step 4: Active Directory Domain

The script expects to connect to a domain named `isaacinthecloud.com`. You will need to adjust the script to meet your needs. 

---

## Step 5: Prepare Input Files

1. Navigate to the `examples/` folder
2. Copy sample CSV files to the repo root:
   ```powershell
   Copy-Item examples\FinancePersonnel_sample.csv src\FinancePersonnel.csv
   Copy-Item examples\NewClientData_sample.csv src\NewClientData.csv
   ```
3. (Optional) Edit the CSV files to add your own test data

---

## Step 6: Verify Setup

Run this verification script to check all prerequisites:

```powershell
# Check PowerShell version
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Check AD module
$ad = Get-Module -ListAvailable -Name ActiveDirectory
if ($ad) { 
    Write-Host "✓ ActiveDirectory module found" -ForegroundColor Green 
} else { 
    Write-Host "✗ ActiveDirectory module NOT found" -ForegroundColor Red 
}

# Check SQL module
$sql = Get-Module -ListAvailable -Name SqlServer
if ($sql) { 
    Write-Host "✓ SqlServer module found" -ForegroundColor Green 
} else { 
    Write-Host "✗ SqlServer module NOT found" -ForegroundColor Red 
}

# Check admin rights
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "✓ Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "⚠ Not running as Administrator" -ForegroundColor Yellow
}
```

---

## Troubleshooting

### "ActiveDirectory module not found"
- Ensure RSAT tools are installed
- On Windows 10/11, check Settings > Apps > Optional Features

### "Cannot connect to SQL Server"
- Verify SQL Server service is running
- Check the instance name matches your configuration
- Ensure SQL Server allows remote connections (if not localhost)

### "Access denied" errors
- Run PowerShell as Administrator
- Verify your account has Domain Admin rights
- Check SQL Server permissions

### "Domain not found"
- Ensure your computer is joined to the domain
- Verify DNS is resolving the domain correctly
- Check network connectivity to domain controller

---

## Next Steps

Once installation is complete:
1. Read [USAGE.md](USAGE.md) for execution instructions
2. Review [ARCHITECTURE.md](ARCHITECTURE.md) to understand the script design
