# SteamDNS.ps1 - Doi DNS de vao Steam, va khoi phuc lai DNS cu
# Chay bang SteamDNS.bat (tu xin quyen Admin)

$ErrorActionPreference = 'Stop'
$BackupFile = Join-Path $PSScriptRoot 'dns-backup.json'

$Presets = [ordered]@{
    '1' = @{ Name = 'Cloudflare (1.1.1.1)'; Servers = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001') }
    '2' = @{ Name = 'Google (8.8.8.8)';     Servers = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844') }
    '3' = @{ Name = 'Quad9 (9.9.9.9)';      Servers = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9') }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ActiveAdapters {
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual }
}

function Get-StaticDns($adapter) {
    # Doc registry de biet DNS dang dat tay (static) hay lay tu DHCP
    $guid = $adapter.InterfaceGuid
    $v4 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $v6 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid" -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $list = @()
    foreach ($s in @($v4, $v6)) { if ($s) { $list += ($s -split '[,\s]+' | Where-Object { $_ }) } }
    return $list
}

function Show-Status {
    Write-Host ''
    foreach ($a in Get-ActiveAdapters) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex | ForEach-Object ServerAddresses) -join ', '
        $mode = if (@(Get-StaticDns $a).Count -gt 0) { 'Thu cong' } else { 'Tu dong (DHCP)' }
        Write-Host ("  [{0}] DNS: {1}  ({2})" -f $a.Name, $dns, $mode)
    }
    if (Test-Path $BackupFile) { Write-Host "  * Da co ban sao luu DNS cu." -ForegroundColor DarkGray }
    Write-Host ''
}

function Save-Backup {
    if (Test-Path $BackupFile) {
        Write-Host 'Da co ban sao luu tu truoc -> giu nguyen (de khong ghi de DNS goc).' -ForegroundColor DarkGray
        return
    }
    $data = foreach ($a in Get-ActiveAdapters) {
        [pscustomobject]@{ Name = $a.Name; Guid = "$($a.InterfaceGuid)"; Static = @(Get-StaticDns $a) }
    }
    ConvertTo-Json @($data) -Depth 3 | Set-Content -Path $BackupFile -Encoding UTF8
    Write-Host "Da sao luu DNS cu vao dns-backup.json" -ForegroundColor Green
}

function Set-SteamDns($preset) {
    Save-Backup
    foreach ($a in Get-ActiveAdapters) {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $preset.Servers
        Write-Host ("  [{0}] -> {1}" -f $a.Name, $preset.Name) -ForegroundColor Green
    }
    Clear-DnsClientCache
    Write-Host 'Da xoa cache DNS. Hay khoi dong lai Steam.' -ForegroundColor Cyan
}

function Restore-Dns {
    $backup = $null
    if (Test-Path $BackupFile) { $backup = @(Get-Content $BackupFile -Raw | ConvertFrom-Json) }
    foreach ($a in Get-ActiveAdapters) {
        $entry = $backup | Where-Object { $_.Guid -eq "$($a.InterfaceGuid)" } | Select-Object -First 1
        # Lam phang mang (ban sao luu cu co the bi long [[ ]]) va bo phan tu rong
        $servers = @()
        if ($entry) { $servers = @($entry.Static | ForEach-Object { $_ } | Where-Object { $_ }) }
        if ($servers.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers
            Write-Host ("  [{0}] -> khoi phuc: {1}" -f $a.Name, ($servers -join ', ')) -ForegroundColor Green
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses
            Write-Host ("  [{0}] -> ve Tu dong (DHCP)" -f $a.Name) -ForegroundColor Green
        }
    }
    if (Test-Path $BackupFile) { Remove-Item $BackupFile -Force }
    Clear-DnsClientCache
    Write-Host 'Da khoi phuc DNS va xoa cache.' -ForegroundColor Cyan
}

if (-not (Test-Admin)) {
    Write-Host 'Can quyen Administrator. Hay chay bang SteamDNS.bat.' -ForegroundColor Red
    Read-Host 'Nhan Enter de thoat'
    exit 1
}

while ($true) {
    Clear-Host
    Write-Host '========== STEAM DNS TOOL ==========' -ForegroundColor Yellow
    Show-Status
    foreach ($k in $Presets.Keys) { Write-Host "  $k. Doi sang $($Presets[$k].Name)" }
    Write-Host '  R. Khoi phuc DNS cu'
    Write-Host '  Q. Thoat'
    $c = (Read-Host "`nChon").Trim().ToUpper()
    try {
        if ($Presets.Contains($c)) { Set-SteamDns $Presets[$c] }
        elseif ($c -eq 'R') { Restore-Dns }
        elseif ($c -eq 'Q') { break }
        else { continue }
    } catch {
        Write-Host "Loi: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host "`nNhan Enter de tiep tuc"
}
