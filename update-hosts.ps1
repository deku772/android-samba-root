#!/usr/bin/env powershell
#=============================================================
# Update Windows hosts file: map phone hostname to current IP
#
# Usage:
#   .\update-hosts.ps1                    # Auto-detect phone IP
#   .\update-hosts.ps1 -Hostname k20p     # Specify hostname
#   .\update-hosts.ps1 -Remove            # Remove mapping
#=============================================================
[CmdletBinding()]
param(
    [string]$Hostname = "k20p",
    [string]$DeviceIP = "",
    [switch]$Remove
)

$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$MarkerStart = "# Android-Samba-Hosts-Start"
$MarkerEnd = "# Android-Samba-Hosts-End"

# Get phone IP
if (-not $DeviceIP -and -not $Remove) {
    Write-Host "Detecting phone IP..." -ForegroundColor Cyan
    $adbResult = & adb shell "ip addr show wlan0 2>/dev/null | grep 'inet '" 2>&1
    if ($adbResult -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/') {
        $DeviceIP = $Matches[1]
        Write-Host "Phone IP: $DeviceIP" -ForegroundColor Green
    } else {
        Write-Host "Cannot auto-detect phone IP. Use -DeviceIP parameter." -ForegroundColor Red
        Write-Host 'Usage: .\update-hosts.ps1 -DeviceIP 192.168.1.93' -ForegroundColor Yellow
        exit 1
    }
}

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Need admin privileges to modify hosts file. Elevating..." -ForegroundColor Yellow
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($Hostname) { $args += "-Hostname", $Hostname }
    if ($DeviceIP) { $args += "-DeviceIP", $DeviceIP }
    if ($Remove) { $args += "-Remove" }
    Start-Process powershell -Verb RunAs -ArgumentList $args -Wait
    exit
}

# Read current hosts file
$content = Get-Content $HostsFile -ErrorAction Stop
$newContent = [System.Collections.ArrayList]@()
$inSection = $false

foreach ($line in $content) {
    if ($line -match $MarkerStart) { $inSection = $true; continue }
    if ($line -match $MarkerEnd) { $inSection = $false; continue }
    if (-not $inSection) { [void]$newContent.Add($line) }
}

if ($Remove) {
    Write-Host "Removing $Hostname mapping..." -ForegroundColor Cyan
    Set-Content -Path $HostsFile -Value $newContent -Encoding ASCII
    Write-Host "Removed $Hostname mapping" -ForegroundColor Green
    exit 0
}

# Add new mapping
[void]$newContent.Add("")
[void]$newContent.Add($MarkerStart)
[void]$newContent.Add("$DeviceIP $Hostname  # Android Samba (auto-updated)")
[void]$newContent.Add($MarkerEnd)

# Write hosts file
Set-Content -Path $HostsFile -Value $newContent -Encoding ASCII
Write-Host ""
Write-Host "hosts file updated:" -ForegroundColor Green
Write-Host "  $DeviceIP $Hostname" -ForegroundColor White
Write-Host ""
Write-Host "Access via:" -ForegroundColor Cyan
Write-Host "  \\$Hostname\sdcard" -ForegroundColor White
Write-Host "  \\$Hostname\xunlei" -ForegroundColor White
Write-Host ""
Write-Host "Test: ping $Hostname" -ForegroundColor Yellow

# Verify
$pingResult = & ping -n 1 $Hostname 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: $Hostname is reachable" -ForegroundColor Green
} else {
    Write-Host "ping failed, flushing DNS cache..." -ForegroundColor Yellow
    & ipconfig /flushdns 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $pingResult2 = & ping -n 1 $Hostname 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK after flush: $Hostname is reachable" -ForegroundColor Green
    } else {
        Write-Host "Still failing. Try: ipconfig /flushdns" -ForegroundColor Yellow
    }
}
