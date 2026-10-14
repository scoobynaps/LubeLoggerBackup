Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "================================================================" -ForegroundColor DarkRed
Write-Host "      __          __         __                                 " -ForegroundColor DarkYellow
Write-Host "     / /   __  __/ /_  ___  / /   ____  ____  ____  ___  _____  " -ForegroundColor Yellow
Write-Host "    / /   / / / / __ \/ _ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/  " -ForegroundColor DarkYellow
Write-Host "   / /___/ /_/ / /_/ /  __/ /___/ /_/ / /_/ / /_/ /  __/ /      " -ForegroundColor Yellow
Write-Host "  /_____/\__,_/_.___/\___/_____/\____/\__, /\__, /\___/_/       " -ForegroundColor DarkYellow
Write-Host "                                     /____//____/               " -ForegroundColor DarkYellow
Write-Host "                       BACKUP UTILITY                           " -ForegroundColor DarkCyan
Write-Host "================================================================" -ForegroundColor DarkRed
Write-Host ""


#=======================#
#                       #
# --- CONFIGURATION --- #
#                       #
#=======================#

# Runs without the progress bar. Only comment out line when testing in PowerShell window.
 $ProgressPreference = 'SilentlyContinue'

# Backup Directory - Backup path (Accepts drive letters and share paths but use share paths when using Task Scheduler.)
$BackupDir = "\\share_location_here\"

# File Name - First part of the file name before the date/time stamp.
$Filename = "db_backup"

# Date - Date format that is appended to the backup file name.
$Date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"

# URL - URL including the port of your LubeLogger instance.
$LubeLoggerUrl = "http://your_ip_here:5000"

# Athentication - Root credentials for LubeLogger if authentication is enabled. If disabled, leave blank.
$RootUser = "username_here"
$RootPassword = "password_here"

# Temporary Files and Unlink Attachments Cleanup - Clears temp folder along with unlinked attachments using the cleanup API with deepClean. (true enables, anything else disables).
$CleanupTempFilesandUnlinkedAttachments = "true"

# Backup Retention Period - How long to keep backups (in days) before the oldest backups are removed. Anything less than 7 will be ignored and set to 7 or 1 full week.
$BackupRetentionPeriod = 365


#=====================================#
#                                     #
# --- DO NOT EDIT BELOW THIS LINE --- #
#                                     #
#=====================================#

$FilenameDate = "${Filename}_$Date.zip"
$DestinationPath = Join-Path $BackupDir $FilenameDate

# Set up Basic Authentication header
$Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${RootUser}:${RootPassword}"))
$Headers = @{
    "Authorization" = "Basic $Base64AuthInfo"
}

Write-Host "--- Starting LubeLogger Backup ---" -ForegroundColor DarkYellow
Write-Host ""

# 1. Ensure the backup directory exists
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

# 2. Trigger the backup using Basic Auth and capture the returned path
Write-Host "Requesting backup from LubeLogger..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$LubeLoggerUrl/api/makebackup" -Method Get -Headers $Headers -ErrorAction Stop
    $BackupPath = $Response.ToString().Trim('"')
}
catch {
    Write-Host ""
    Write-Host "Error: Failed to trigger backup - $_" -ForegroundColor DarkRed
    Write-Host ""
    exit 1
}

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    Write-Host ""
    Write-Host "Error: Received empty response from LubeLogger" -ForegroundColor DarkRed
    Write-Host ""
    exit 1
}

# Ensure clean URL construction
$DownloadUrl = "$($LubeLoggerUrl.TrimEnd('/'))$($BackupPath)"
Write-Host "Downloading backup from $DownloadUrl..." -ForegroundColor DarkCyan

# 3. Download the backup zip using the same Basic Auth header
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $DestinationPath -Headers $Headers -ErrorAction Stop
}
catch {
    Write-Host ""
    Write-Host "Error: Failed to download backup file - $_" -ForegroundColor DarkRed
    Write-Host ""
    exit 1
}

# 4. Verify the downloaded file is a valid ZIP archive
$FileHeader = Get-Content -Encoding Byte -TotalCount 4 -Path $DestinationPath -ErrorAction SilentlyContinue
if (-not $FileHeader -or $FileHeader[0] -eq 0x3C -or $FileHeader[0] -eq 0x48) { 
    Write-Host ""
    Write-Host "Error: The downloaded file is not a valid ZIP archive (received HTML login/error page)." -ForegroundColor DarkRed
    Write-Host ""
    Remove-Item $DestinationPath -Force
    exit 1
}

if ((Get-Item $DestinationPath).Length -lt 1024) {
    Write-Host ""
    Write-Host "Error: Downloaded backup file is suspiciously small." -ForegroundColor DarkRed
    Write-Host ""
    Remove-Item $DestinationPath -Force
    exit 1
}

Write-Host ""
Write-Host "--- Backup Successful! ---" -ForegroundColor DarkGreen
Write-Host "Location: $DestinationPath" -ForegroundColor DarkGreen
Write-Host ""

# 5. Cleanup temporary files and unlinked attachments (if configured)
if ($CleanupTempFilesandUnlinkedAttachments -eq "true") {
Write-Host "Cleaning temporary files and unlinked attachments..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$LubeLoggerUrl/api/cleanup?deepClean=true" -Method Get -Headers $Headers -ErrorAction Stop
    Write-Host "Temporary files and unlinked attachments cleanup successful!" -ForegroundColor DarkGreen
    Write-Host ""
} catch {
    Write-Host "Error: Failed to cleanup temporary files and unlinked attachments - $_" -ForegroundColor DarkRed
    Write-Host ""
}
}

# 6. Cleanup backups older than the backup retention period days (ignores values less than 7 and makes the value 7 or 1 full week).
if ($BackupRetentionPeriod -lt 7) {
    $BackupRetentionPeriod = 7
}

Write-Host "Cleaning up backups older than $BackupRetentionPeriod days..." -ForegroundColor Yellow
$ThresholdDate = (Get-Date).AddDays(-$BackupRetentionPeriod)
$OldBackups = Get-ChildItem -Path $BackupDir -Filter "*.zip" | Where-Object { $_.LastWriteTime -lt $ThresholdDate }

if ($OldBackups) {
    foreach ($Backup in $OldBackups) {
        Write-Host "Deleting old backup: $($Backup.FullName)" -ForegroundColor Yellow
        Remove-Item $Backup.FullName -Force
    }
} else {
    Write-Host "No backups older than $BackupRetentionPeriod days were found!" -ForegroundColor DarkGreen
}

Write-Host ""
Write-Host "--- LubeLogger Task Completed ---" -ForegroundColor DarkYellow
Write-Host ""
exit 0
