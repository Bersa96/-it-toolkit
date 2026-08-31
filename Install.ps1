$ErrorActionPreference = 'Continue'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[INFO] Requesting Administrator Privileges..." -ForegroundColor Yellow
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        # Prefer the exact local file the user launched. This avoids executing mutable
        # remote content inside an elevated Invoke-Expression process.
        Start-Process powershell.exe -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
            '-File', "`"$PSCommandPath`""
        ) -Verb RunAs
    } else {
        # Keep the public GitHub one-liner workflow working, but download to a file
        # first so Windows can execute and audit a normal script instead of piping
        # internet content directly into an elevated Invoke-Expression session.
        $url = 'https://raw.githubusercontent.com/Bersa96/-it-toolkit/main/Install.ps1'
        $downloadedScript = Join-Path ([IO.Path]::GetTempPath()) "IT-Toolkit-$([Guid]::NewGuid().ToString('N')).ps1"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $downloadedScript -UseBasicParsing -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $downloadedScript) -or (Get-Item -LiteralPath $downloadedScript).Length -lt 100) {
                throw 'Downloaded script is empty or incomplete.'
            }
            $downloadHash = (Get-FileHash -LiteralPath $downloadedScript -Algorithm SHA256).Hash
            Write-Host "[INFO] Downloaded toolkit SHA256: $downloadHash" -ForegroundColor DarkGray
            Start-Process powershell.exe -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
                '-File', "`"$downloadedScript`""
            ) -Verb RunAs
        } catch {
            Write-Host "[ERROR] Unable to download the toolkit safely: $($_.Exception.Message)" -ForegroundColor Red
            Read-Host 'Press Enter to exit' | Out-Null
        }
    }
    exit
}

function Get-ToolkitPhysicalAdapters {
    @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and
                $_.HardwareInterface -eq $true -and
                $_.InterfaceDescription -notmatch 'Bluetooth'
            }
    )
}

function Select-ToolkitPhysicalAdapter {
    param([string]$Prompt = 'Select the physical network adapter')

    $adapters = @(Get-ToolkitPhysicalAdapters)
    if ($adapters.Count -eq 0) {
        Write-Host '[ERROR] No active physical Wi-Fi or Ethernet adapter was found.' -ForegroundColor Red
        return $null
    }
    if ($adapters.Count -eq 1) { return $adapters[0] }

    Write-Host "`n$Prompt" -ForegroundColor Cyan
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        Write-Host ("   [{0}] {1} - {2} ({3})" -f ($i + 1), $adapters[$i].Name, $adapters[$i].InterfaceDescription, $adapters[$i].LinkSpeed)
    }
    $selectionText = Read-Host "Adapter number (default: 1)"
    if ([string]::IsNullOrWhiteSpace($selectionText)) { $selectionText = '1' }
    try { $selection = [int]$selectionText } catch { $selection = 0 }
    if ($selection -lt 1 -or $selection -gt $adapters.Count) {
        Write-Host '[ERROR] Invalid adapter selection.' -ForegroundColor Red
        return $null
    }
    return $adapters[$selection - 1]
}

function Test-ToolkitIPv4Address {
    param([string]$Address)
    $parsedAddress = $null
    return [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -and
        $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function Get-ToolkitDeploymentCredential {
    if ($script:ToolkitDeploymentCredential) { return $script:ToolkitDeploymentCredential }

    $deploymentUser = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_DEPLOY_USER')
    if ([string]::IsNullOrWhiteSpace($deploymentUser)) {
        $deploymentUser = '192.168.10.160\ls_deploy'
    }
    $deploymentPassword = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_DEPLOY_PASSWORD')
    if ([string]::IsNullOrWhiteSpace($deploymentPassword)) {
        $deploymentPassword = 'Ls@Deploy2026!'
    }
    $secureDeploymentPassword = ConvertTo-SecureString $deploymentPassword -AsPlainText -Force
    $script:ToolkitDeploymentCredential = New-Object System.Management.Automation.PSCredential($deploymentUser, $secureDeploymentPassword)
    return $script:ToolkitDeploymentCredential
}

function Connect-ToolkitDeploymentShare {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Root
    )

    Remove-PSDrive -Name $Name -Force -ErrorAction SilentlyContinue
    $credential = Get-ToolkitDeploymentCredential
    if (-not $credential) { return $false }
    try {
        New-PSDrive -Name $Name -PSProvider FileSystem -Root $Root -Credential $credential -Scope Script -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host "[ERROR] Unable to connect to $Root : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

while ($true) {
    Clear-Host
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "                    IT SUPPORT TOOLKIT - MASTER MENU                     " -ForegroundColor Cyan
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [ DEPLOYMENT & ONBOARDING ]" -ForegroundColor Yellow
    Write-Host "   [1] Standard App Deployment       (Chrome, Acrobat, Office Tools, AnyDesk, Zoom)"
    Write-Host "   [2] Performance & Low-End Tuning  (HDD 100% Fix, Smart SSD TRIM, Memory Saver)"
    Write-Host "   [3] System Integrity Repair       (SFC Scannow & DISM Component Cleanup)"
    Write-Host "   [4] Printer & Spooler Recovery    (Fix Offline, WSD to TCP/IP Migration, Clear Queue)"
    Write-Host ""
    Write-Host "  [ DIAGNOSTICS & SYSTEM REPAIR ]" -ForegroundColor Yellow
    Write-Host "   [5] Network & DHCP Recovery       (Fix 169.254 APIPA, Stack Reset, Export Diagnostics)"
    Write-Host "   [6] Windows Update Controller     (Dynamic 9999-Day Pause / Resume)"
    Write-Host "   [7] Lansweeper Asset Onboarding   (Hostname Policy, Admin Profile, LsAgent Setup)"
    Write-Host "   [8] Kaspersky Endpoint Deployment (Legacy AV Remnant Purge & Clean Setup)"
    Write-Host ""
    Write-Host "  [ COMPLIANCE & TELEMETRY CONTROL ]" -ForegroundColor Yellow
    Write-Host "   [9] Software Telemetry Blocker    (AutoCAD All Versions, EaseUS Suite, Hosts & Firewall)"
    Write-Host ""
    Write-Host "  [ NETWORKING & REMOTE ACCESS ]" -ForegroundColor Yellow
    Write-Host "   [10] SMB Share & Stealth Manager  (Hidden $ Shares, Broadcast Visibility Toggle)"
    Write-Host "   [11] High-Speed LAN Scanner       (Multithreaded Subnet & Host Discovery)"
    Write-Host "   [12] Remote Desktop (RDP) Manager (Enable RDP Server, Windows Home RDPWrap Bypass)"
    Write-Host ""
    Write-Host "   [0] Exit" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Select option (0-12)"

    switch ($choice) {
        "1" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "                    STANDARD APPS INSTALLER MANAGER                      " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   [A] Install All Standard Apps (Bulk Install Everything Below)" -ForegroundColor Green
                Write-Host ""
                Write-Host "   --- Select Individual App to Install ---" -ForegroundColor Yellow
                Write-Host "   [1] Google Chrome            (Web Browser)"
                Write-Host "   [2] Adobe Acrobat Reader DC  (PDF Reader)"
                Write-Host "   [3] PDF24 Creator            (PDF Tools & Editor)"
                Write-Host "   [4] WhatsApp Desktop         (Messaging App)"
                Write-Host "   [5] 7-Zip (64-bit)           (Archive Extractor)"
                Write-Host "   [6] VLC Media Player         (Video & Audio Player)"
                Write-Host "   [7] AnyDesk Remote Desktop   (Remote Support Tool)"
                Write-Host "   [8] Zoom Workplace           (Video Conferencing)"
                Write-Host "   [9] Notion                   (Notes & Collaboration)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $appChoice = Read-Host "Select option (A / 1-9 / 0)"

                $appDefs = @{
                    "1" = @{ name = "Google Chrome";           id = "Google.Chrome";                  url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"; out = "$env:TEMP\Chrome.exe"; args = "/silent /install" }
                    "2" = @{ name = "Adobe Acrobat Reader";    id = "Adobe.Acrobat.Reader.64-bit";    url = "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2400120604/AcroRdrDC2400120604_en_US.exe"; out = "$env:TEMP\Acrobat.exe"; args = "/sAll /rs" }
                    "3" = @{ name = "PDF24 Creator";           id = "geekwright.PDF24";               url = "https://download.pdf24.org/pdf24-creator-11.15.2-x64.exe"; out = "$env:TEMP\PDF24.exe"; args = "/VERYSILENT /NORESTART" }
                    "4" = @{ name = "WhatsApp Desktop";        id = "WhatsApp.WhatsApp";               url = "https://desktop.whatsapp.com/releases/WinX64/WhatsAppSetup.exe"; out = "$env:TEMP\WA.exe"; args = "/silent" }
                    "5" = @{ name = "7-Zip";                   id = "7zip.7zip";                      url = "https://www.7-zip.org/a/7z2408-x64.exe"; out = "$env:TEMP\7zip.exe"; args = "/S" }
                    "6" = @{ name = "VLC Media Player";        id = "VideoLAN.VLC";                   url = "https://get.videolan.org/vlc/3.0.21/win64/vlc-3.0.21-win64.exe"; out = "$env:TEMP\VLC.exe"; args = "/S" }
                    "7" = @{ name = "AnyDesk";                 id = "AnyDeskSoftwareGmbH.AnyDesk";   url = "https://download.anydesk.com/AnyDesk.exe"; out = "$env:TEMP\AnyDesk.exe"; args = "--install `"C:\Program Files (x86)\AnyDesk`" --start-with-win --silent" }
                    "8" = @{ name = "Zoom";                    id = "Zoom.Zoom";                      url = "https://zoom.us/client/latest/ZoomInstaller.exe"; out = "$env:TEMP\Zoom.exe"; args = "/silent" }
                    "9" = @{ name = "Notion";                  id = "Notion.Notion";                  url = "https://www.notion.so/desktop/windows/download"; out = "$env:TEMP\Notion.exe"; args = "/S" }
                }

                if ($appChoice -eq "0") {
                    break
                }

                $selectedApps = @()
                if ($appChoice.ToUpper() -eq "A") {
                    $selectedApps = @($appDefs["1"], $appDefs["2"], $appDefs["3"], $appDefs["4"], $appDefs["5"], $appDefs["6"], $appDefs["7"], $appDefs["8"], $appDefs["9"])
                } elseif ($appDefs.ContainsKey($appChoice)) {
                    $selectedApps = @($appDefs[$appChoice])
                } else {
                    Write-Host "`n[ERROR] Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

                foreach ($app in $selectedApps) {
                    Write-Host "`nProcessing $($app.name)..." -ForegroundColor Yellow
                    
                    $installed = $false
                    $offlineInstaller = $null

                    # 1. Search for Offline Installer on Connected USB / Flash Drives, Local D:\, or Network Share
                    $searchLocations = @()
                    $removableDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
                    foreach ($drive in $removableDrives) {
                        $searchLocations += "$($drive):\Software"
                        $searchLocations += "$($drive):\software\Software"
                        $searchLocations += "$($drive):\software\soft"
                        $searchLocations += "$($drive):\soft"
                        $searchLocations += "$($drive):\"
                    }
                    $searchLocations += "D:\Sharing\Software"
                    $searchLocations += "D:\Backup\Software"
                    $searchLocations += "\\192.168.10.160\Sharing\Software"

                    $patterns = @("$($app.name)*.exe", "$($app.name)*.msi")
                    if ($app.name -like "*Chrome*") { $patterns += @("*chrome*.exe", "*ChromeSetup*.exe") }
                    if ($app.name -like "*Acrobat*") { $patterns += @("*AcroRdr*.exe", "*Acrobat*.exe") }
                    if ($app.name -like "*PDF24*") { $patterns += @("*pdf24*.exe") }
                    if ($app.name -like "*WhatsApp*") { $patterns += @("*WhatsApp*.exe", "*WA*.exe") }
                    if ($app.name -like "*7-Zip*") { $patterns += @("*7z*.exe", "*7-zip*.exe") }
                    if ($app.name -like "*VLC*") { $patterns += @("*vlc*.exe") }
                    if ($app.name -like "*AnyDesk*") { $patterns += @("*AnyDesk*.exe") }
                    if ($app.name -like "*Zoom*") { $patterns += @("*Zoom*.exe", "*ZoomInstaller*.exe") }
                    if ($app.name -like "*Notion*") { $patterns += @("*Notion*.exe", "*NotionSetup*.exe") }

                    foreach ($loc in ($searchLocations | Select-Object -Unique)) {
                        if (Test-Path $loc) {
                            foreach ($pat in $patterns) {
                                $found = Get-ChildItem -Path $loc -Filter $pat -File -ErrorAction SilentlyContinue | Select-Object -First 1
                                if ($found) {
                                    $offlineInstaller = $found.FullName
                                    break
                                }
                            }
                        }
                        if ($offlineInstaller) { break }
                    }

                    # Execute Offline Installer if found
                    if ($offlineInstaller) {
                        Write-Host "   [Offline Installer] Found on storage ($offlineInstaller). Installing..." -ForegroundColor Green
                        try {
                            $proc = Start-Process -FilePath $offlineInstaller -ArgumentList $app.args -PassThru -ErrorAction Stop
                            $proc.WaitForExit()
                            Write-Host "   [OK] $($app.name) installed from Offline Storage." -ForegroundColor Green
                            $installed = $true
                        } catch {
                            Write-Host "   [WARN] Offline execution failed: $_" -ForegroundColor Yellow
                        }
                    }

                    # 2. Fallback to Winget if offline installer not found
                    if (-not $installed) {
                        Write-Host "   [Winget] Attempting installation via Windows Package Manager..." -ForegroundColor Gray
                        $wingetRes = & winget install --id $app.id --silent --accept-package-agreements --accept-source-agreements --scope machine --override "/silent" 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "   [OK] $($app.name) installed via Winget." -ForegroundColor Green
                            $installed = $true
                        }
                    }
                    
                    # 3. Fallback to Direct Online Vendor Download if Winget fails
                    if (-not $installed) {
                        Write-Host "   [Direct Download] Downloading latest version from vendor..." -ForegroundColor Gray
                        try {
                            if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                                Start-BitsTransfer -Source $app.url -Destination $app.out -ErrorAction Stop
                            } else {
                                Invoke-WebRequest -Uri $app.url -OutFile $app.out -UseBasicParsing -ErrorAction Stop
                            }
                            
                            if (Test-Path $app.out) {
                                $proc = Start-Process -FilePath $app.out -ArgumentList $app.args -PassThru -ErrorAction Stop
                                $proc.WaitForExit()
                                Remove-Item $app.out -Force -ErrorAction SilentlyContinue
                                Write-Host "   [OK] $($app.name) installed successfully." -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "   [WARN] Direct download failed for $($app.name): $_" -ForegroundColor Red
                        }
                    }
                }

                Write-Host "`n[OK] Installation completed." -ForegroundColor Green
                Start-Sleep -Seconds 2
            }
        }
        "2" {
            while ($true) {
                Clear-Host
                
                # Detect Hardware Specs (Drive Type & RAM Size)
                $driveC = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
                $diskType = "Unknown / HDD"
                try {
                    $part = Get-Partition -DriveLetter C -ErrorAction SilentlyContinue
                    if ($part) {
                        $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue
                        if ($disk) {
                            if ($disk.MediaType -eq "SSD" -or $disk.BusType -in @("NVMe", "SATA") -and $disk.FriendlyName -match "SSD|NVMe|NAND|Flash|eMMC") {
                                $diskType = "SSD ($($disk.BusType) - $($disk.FriendlyName))"
                            } elseif ($disk.MediaType -eq "HDD") {
                                $diskType = "HDD (Mechanical Hard Disk)"
                            } else {
                                $diskType = "$($disk.MediaType) ($($disk.BusType))"
                            }
                        }
                    }
                } catch { $diskType = "Drive C: Generic" }

                $ramTotalGB = [math]::Round(((Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum / 1GB), 1)

                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "          WINDOWS PERFORMANCE & POTATO PC OPTIMIZER (RAM/DISK)           " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   Detected Storage (C:) : $diskType" -ForegroundColor Yellow
                Write-Host "   Detected Total RAM    : $ramTotalGB GB" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "   [1] Smart Auto-Boost         (Auto-Tune based on detected Hardware & RAM)" -ForegroundColor Green
                Write-Host ""
                Write-Host "   --- Target Performance Profiles ---" -ForegroundColor Yellow
                Write-Host "   [2] Mechanical HDD 100% Fix  (Stop SysMain/Superfetch, Indexing, Prefetch)"
                Write-Host "   [3] SSD Health & TRIM Tune   (Enable TRIM, Re-Trim I/O, Disable Bad Defrag)"
                Write-Host "   [4] Low RAM / Memory Saver   (Optimized Pagefile, Kill Background Extensions)"
                Write-Host "   [5] Strip Visual Animations  (Best Performance UI, Keep Fonts Crisp & Smooth)"
                Write-Host "   [6] Standard Windows Tweaks  (Dark Mode, Classic Explorer, File Extensions)"
                Write-Host "   [7] Safe AppX Bloatware Purge (Remove Junk Games, Ads, News, Weather & Cortana)"
                Write-Host "   [8] Revert / Restore Default (Restore SysMain, Visual Effects & Settings)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $tweakChoice = Read-Host "Select option (0-8)"
                if ($tweakChoice -eq "0") {
                    break
                }
                switch ($tweakChoice) {
                    "1" {
                        Write-Host "`nRunning Smart Auto-Boost for detected Hardware ($diskType, ${ramTotalGB}GB RAM)..." -ForegroundColor Yellow
                        
                        # 1. UI Tweaks (Dark Mode & Explorer)
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\DeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f >$null 2>&1
                        
                        # 2. Disable Background Bloatware & Telemetry
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >$null 2>&1
                        
                        # 3. Disable Edge Startup Boost & Background Extensions (Save 400MB+ RAM)
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f >$null 2>&1

                        # 4. Storage specific optimization
                        if ($diskType -match "SSD") {
                            Write-Host "   [SSD Profile Applied] Running TRIM & Optimizing SSD I/O..." -ForegroundColor Cyan
                            fsutil behavior set DisableDeleteNotify 0 >$null 2>&1
                            Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue
                        } else {
                            Write-Host "   [HDD Profile Applied] Disabling SysMain & Prefetcher (Fixing 100% Disk Usage)..." -ForegroundColor Cyan
                            Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                            Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
                            reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f >$null 2>&1
                            reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 0 /f >$null 2>&1
                        }

                        # 5. Low RAM strip visual effects if RAM <= 8GB
                        if ($ramTotalGB -le 8) {
                            Write-Host "   [Low RAM Tuning] Disabling heavy UI animations while keeping clean fonts..." -ForegroundColor Cyan
                            reg add "HKCU\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f >$null 2>&1
                            reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >$null 2>&1
                            reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >$null 2>&1
                            reg add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 50 /f >$null 2>&1
                        }

                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        Start-Process explorer
                        Write-Host "`n[OK] Smart Auto-Boost applied successfully!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        Write-Host "`nApplying Aggressive HDD 100% Disk Usage Fix..." -ForegroundColor Yellow
                        
                        # 1. Stop and Disable SysMain (Superfetch)
                        Write-Host "   [1/4] Disabling SysMain (Superfetch) Service..." -ForegroundColor Gray
                        Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                        Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue

                        # 2. Disable Prefetch & Superfetch in Registry
                        Write-Host "   [2/4] Disabling Prefetch Parameters in Memory Management..." -ForegroundColor Gray
                        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 0 /f >$null 2>&1

                        # 3. Disable Connected User Experiences & Telemetry (DiagTrack)
                        Write-Host "   [3/4] Stopping Background Telemetry Logging (DiagTrack)..." -ForegroundColor Gray
                        Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
                        Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

                        # 4. Limit Windows Search Indexing on Slow Drives
                        Write-Host "   [4/4] Optimizing Windows Search Indexing..." -ForegroundColor Gray
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v PreventIndexingLowDiskSpaceMB /t REG_DWORD /d 500 /f >$null 2>&1

                        Write-Host "`n[OK] Mechanical HDD Disk 100% mitigations applied successfully!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        Write-Host "`nApplying SSD Health & TRIM Performance Optimization..." -ForegroundColor Yellow
                        
                        # 1. Enable and verify TRIM
                        Write-Host "   [1/3] Enabling NTFS/ReFS TRIM Notifications (fsutil)..." -ForegroundColor Gray
                        fsutil behavior set DisableDeleteNotify 0 >$null 2>&1

                        # 2. Disable automatic defragmentation on SSD
                        Write-Host "   [2/3] Configuring Storage Defragmenter to Re-Trim mode only..." -ForegroundColor Gray
                        reg add "HKLM\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction" /v Enable /t REG_SZ /d "N" /f >$null 2>&1

                        # 3. Trigger manual Re-Trim on Drive C:
                        Write-Host "   [3/3] Executing live Re-Trim command on Drive C:..." -ForegroundColor Gray
                        Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue

                        Write-Host "`n[OK] SSD Health & TRIM tuning completed!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "4" {
                        Write-Host "`nApplying Low RAM & Memory Saver Profile..." -ForegroundColor Yellow
                        
                        # 1. Disable Edge background extension & startup preload
                        Write-Host "   [1/3] Disabling Edge Preload and Background Extensions (Saves ~400MB RAM)..." -ForegroundColor Gray
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f >$null 2>&1

                        # 2. Disable Background GameDVR & Xbox capture
                        Write-Host "   [2/3] Disabling GameDVR / Xbox background screen recording..." -ForegroundColor Gray
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >$null 2>&1

                        # 3. Disable Background Telemetry & Content Delivery Manager
                        Write-Host "   [3/3] Disabling Silent App Downloads & Telemetry..." -ForegroundColor Gray
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >$null 2>&1

                        Write-Host "`n[OK] Low RAM Memory Saver settings applied!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "5" {
                        Write-Host "`nStripping Heavy Visual Animations (Optimizing for Performance)..." -ForegroundColor Yellow
                        
                        # Set Best Performance mask while keeping font smoothing & thumbnails
                        reg add "HKCU\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f >$null 2>&1
                        reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 50 /f >$null 2>&1
                        
                        # Ensure font smoothing remains ON for readability
                        reg add "HKCU\Control Panel\Desktop" /v FontSmoothing /t REG_SZ /d 2 /f >$null 2>&1
                        reg add "HKCU\Control Panel\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f >$null 2>&1

                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        Start-Process explorer
                        
                        Write-Host "[OK] Visual animations stripped and UI responsiveness set to instant." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "6" {
                        Write-Host "`nApplying Standard Windows 11/10 UI Tweaks..." -ForegroundColor Yellow
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" /v "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\DeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f >$null 2>&1
                        
                        reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSecondsInSystemClock /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSecondsInSystemClock /t REG_DWORD /d 0 /f >$null 2>&1
                        reg add "HKCU\Control Panel\International" /v sShortTime /t REG_SZ /d "HH:mm" /f >$null 2>&1
                        
                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        Start-Process explorer
                        Write-Host "[OK] Standard UI tweaks applied." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "7" {
                        Write-Host "`nPurging Safe AppX Junk Bloatware (Games, Promo Apps, News, Cortana)..." -ForegroundColor Yellow
                        Write-Host "      [Safety Rule] Keeping Calculator, Photos, Store, Paint, Notepad intact." -ForegroundColor Gray
                        
                        $safeBloatwareList = @(
                            "*CandyCrush*", "*Disney*", "*BubbleWitch*", "*FarmHeroes*", "*MarchofEmpires*",
                            "*SolitaireCollection*", "*TikTok*", "*Instagram*", "*Facebook*", "*SpotifyAB.SpotifyMusic*",
                            "*Microsoft.BingNews*", "*Microsoft.BingWeather*", "*Microsoft.BingSports*", "*Microsoft.BingFinance*",
                            "*Microsoft.3DBuilder*", "*Microsoft.MixedReality.Portal*", "*Microsoft.GetHelp*",
                            "*Microsoft.Getstarted*", "*Microsoft.MicrosoftOfficeHub*", "*Microsoft.People*",
                            "*Microsoft.SkypeApp*", "*Microsoft.YourPhone*", "*Microsoft.ZuneMusic*", "*Microsoft.ZuneVideo*",
                            "*Microsoft.549981C3F5F10*", "*Clipchamp*", "*Microsoft.Todos*"
                        )

                        $removedCount = 0
                        foreach ($pkg in $safeBloatwareList) {
                            $apps = Get-AppxPackage -AllUsers $pkg -ErrorAction SilentlyContinue
                            foreach ($app in $apps) {
                                try {
                                    Write-Host "   [-] Removing: $($app.Name)..." -ForegroundColor DarkGray
                                    Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                                    $removedCount++
                                } catch {}
                            }
                            $provApps = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pkg }
                            foreach ($prov in $provApps) {
                                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
                            }
                        }

                        # Disable Windows Consumer Features / Silent App Installations
                        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f >$null 2>&1
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f >$null 2>&1

                        Write-Host "`n[OK] Safe Bloatware Purge complete ($removedCount packages removed)!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "8" {
                        Write-Host "`nRestoring Default Windows Performance Settings..." -ForegroundColor Yellow
                        
                        # 1. Restore SysMain and DiagTrack
                        Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name "SysMain" -ErrorAction SilentlyContinue
                        Set-Service -Name "DiagTrack" -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name "DiagTrack" -ErrorAction SilentlyContinue

                        # 2. Restore Prefetcher
                        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 3 /f >$null 2>&1
                        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 3 /f >$null 2>&1

                        # 3. Restore Visual Effects & Transparency
                        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 1 /f >$null 2>&1
                        reg add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 400 /f >$null 2>&1
                        reg delete "HKCU\Control Panel\Desktop" /v UserPreferencesMask /f >$null 2>&1

                        # 4. Restore Edge policies
                        reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /f >$null 2>&1
                        reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /f >$null 2>&1

                        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                        Start-Process explorer
                        
                        Write-Host "[OK] Default settings restored successfully." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "0" { break }
                }
            }
        }
        "3" {
            Write-Host "`nRunning DISM & SFC..." -ForegroundColor Yellow
            dism /Online /Cleanup-Image /RestoreHealth
            sfc /scannow
            Write-Host "`n[OK] System repair completed." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "4" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "                PRINTER & PRINT SPOOLER TROUBLESHOOTER                   " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   --- Active Installed Printers ---" -ForegroundColor Yellow
                $printers = Get-Printer -ErrorAction SilentlyContinue
                if ($printers) {
                    $printers | Format-Table Name, DriverName, PortName, PrinterStatus -AutoSize | Out-String | Write-Host -ForegroundColor White
                } else {
                    Write-Host "   (No installed printers found)`n" -ForegroundColor Gray
                }
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "   [1] Fast Fix: Clear Stuck Print Queue & Restart Spooler" -ForegroundColor Green
                Write-Host "   [2] Fix Printer Offline (Convert WSD Port to Standard TCP/IP Port)" -ForegroundColor Yellow
                Write-Host "   [3] Disable SNMP Status on TCP/IP Ports (Prevent False Offline Status)"
                Write-Host "   [4] Force Reset 'Use Printer Offline' Flag on All Printers"
                Write-Host "   [5] Quick Add Office Network Printer (Epson Kiri/Kanan, DocuCentre)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $printChoice = Read-Host "Select option (0-5)"
                if ($printChoice -eq "0") {
                    break
                }

                switch ($printChoice) {
                    "1" {
                        Write-Host "`nClearing Print Spooler Queue & Restarting Service..." -ForegroundColor Yellow
                        Stop-Service spooler -Force -ErrorAction SilentlyContinue
                        Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Start-Service spooler -ErrorAction SilentlyContinue
                        Write-Host "[OK] Print spooler queue purged and service restarted cleanly." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        Write-Host "`n=== Convert Printer Port from WSD to Standard TCP/IP ===" -ForegroundColor Yellow
                        if (-not $printers) {
                            Write-Host "[ERROR] No printers found." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }
                        Write-Host "Select Printer to Convert:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $printers.Count; $i++) {
                            Write-Host ("   [{0}] {1} (Current Port: {2})" -f ($i + 1), $printers[$i].Name, $printers[$i].PortName)
                        }
                        $pIndexText = Read-Host "Enter number (1-$($printers.Count))"
                        try { $pIdx = [int]$pIndexText - 1 } catch { $pIdx = -1 }
                        if ($pIdx -ge 0 -and $pIdx -lt $printers.Count) {
                            $selectedPrinter = $printers[$pIdx]
                            $printerIp = Read-Host "Enter Target Printer Static IP (e.g. 192.168.10.155 / 192.168.10.156)"
                            if ($printerIp -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                                $portName = $printerIp
                                $existingPort = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
                                if (-not $existingPort) {
                                    Write-Host "Creating Standard TCP/IP Port: $portName ($printerIp:9100 RAW)..." -ForegroundColor Gray
                                    Add-PrinterPort -Name $portName -PrinterHostAddress $printerIp -PortNumber 9100 -SNMP 0 -ErrorAction SilentlyContinue
                                }
                                Set-Printer -Name $selectedPrinter.Name -PortName $portName -ErrorAction SilentlyContinue
                                Write-Host "`n[OK] Printer '$($selectedPrinter.Name)' successfully mapped to TCP/IP Port '$portName' (SNMP Disabled)!" -ForegroundColor Green
                            } else {
                                Write-Host "[ERROR] Invalid IPv4 format." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        Write-Host "`nDisabling SNMP Status Checking on all Standard TCP/IP Ports..." -ForegroundColor Yellow
                        $tcpPorts = Get-PrinterPort | Where-Object { $_.PrinterHostAddress }
                        $count = 0
                        foreach ($p in $tcpPorts) {
                            try {
                                Set-PrinterPort -Name $p.Name -SNMP 0 -ErrorAction SilentlyContinue
                                $count++
                            } catch {}
                        }
                        Write-Host "[OK] SNMP Status check disabled on $count TCP/IP port(s) (Prevents false offline triggers)." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "4" {
                        Write-Host "`nResetting 'Use Printer Offline' and Paused status across all printers..." -ForegroundColor Yellow
                        Get-Printer | ForEach-Object {
                            try {
                                Resume-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
                                Set-Printer -Name $_.Name -PrinterStatus Normal -ErrorAction SilentlyContinue
                            } catch {}
                        }
                        Write-Host "[OK] All printer queues unpaused and set to Normal online state." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "5" {
                        Write-Host "`n=== Quick Office Printer Setup ===" -ForegroundColor Yellow
                        Write-Host "   [1] Epson L3250 Kanan (192.168.10.155)"
                        Write-Host "   [2] Epson L3250 Kiri  (192.168.10.156)"
                        Write-Host "   [3] DocuCentre Fuji Xerox (192.168.10.157)"
                        $qChoice = Read-Host "Select option (1-3)"
                        
                        $map = @{
                            "1" = @{ name = "EpsonL3250Kanan"; ip = "192.168.10.155"; driver = "EPSON L3250 Series" }
                            "2" = @{ name = "EpsonL3250Kiri";  ip = "192.168.10.156"; driver = "EPSON L3250 Series" }
                            "3" = @{ name = "DocuCentre-V 2060"; ip = "192.168.10.157"; driver = "FF K545p for DocuCentre-V 2060 PCL 6" }
                        }
                        if ($map.ContainsKey($qChoice)) {
                            $target = $map[$qChoice]
                            Write-Host "`nSetting up $($target.name) at $($target.ip)..." -ForegroundColor Cyan
                            $pPort = $target.ip
                            if (-not (Get-PrinterPort -Name $pPort -ErrorAction SilentlyContinue)) {
                                Add-PrinterPort -Name $pPort -PrinterHostAddress $target.ip -PortNumber 9100 -SNMP 0 -ErrorAction SilentlyContinue
                            }
                            $availDriver = Get-PrinterDriver | Where-Object { $_.Name -like "*$($target.driver)*" } | Select-Object -First 1
                            if ($availDriver) {
                                Add-Printer -Name $target.name -DriverName $availDriver.Name -PortName $pPort -ErrorAction SilentlyContinue
                                Write-Host "[OK] Printer '$($target.name)' added and connected via TCP/IP!" -ForegroundColor Green
                            } else {
                                Write-Host "[WARN] Driver '$($target.driver)' not installed yet on this PC. Port '$pPort' is created." -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
        "5" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "             NETWORK, WI-FI & DHCP TROUBLESHOOTING MANAGER               " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   [1] Safe Network Stack Reset                (DNS, ARP, Winsock; no driver tuning)"
                Write-Host "   [2] Fix 'No IPv4 / No Internet' & DHCP Stuck (Reset DHCP/DNS Services & Renew)"
                Write-Host "   [3] Deep Factory Network Reset (netcfg -d)  (Purge Corrupt Virtual Adapters & Filters)"
                Write-Host "   [4] Reset Hosts File to Factory Default     (Fix Host Resolution Errors)"
                Write-Host "   [5] Set Static IP (Manual Diagnostic Mode)  (Bypass DHCP Issues Instantly)"
                Write-Host "   [6] Set Adapter back to Automatic (DHCP)    (Restore Dynamic IP & DNS)"
                Write-Host "   [7] Export Full Network Diagnostic Log      (Save Detailed Report to Desktop/USB)" -ForegroundColor Magenta
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $netChoice = Read-Host "Select option (0-7)"
                if ($netChoice -eq "0") {
                    break
                }
                switch ($netChoice) {
                    "1" {
                        Write-Host "`nSafe Network Stack Reset" -ForegroundColor Yellow
                        Write-Host "This resets DNS, ARP, Winsock and TCP/IP. It does NOT change roaming," -ForegroundColor Gray
                        Write-Host "preferred band, ECN, congestion control or adapter power settings." -ForegroundColor Gray
                        $confirmReset = Read-Host "Continue? (Y/N)"
                        if ($confirmReset -notmatch '(?i)^y(es)?$') {
                            Write-Host '[INFO] Reset cancelled.' -ForegroundColor Yellow
                            Start-Sleep -Seconds 1
                            break
                        }

                        $targetAdapter = Select-ToolkitPhysicalAdapter -Prompt 'Choose the adapter to validate after reset'
                        if (-not $targetAdapter) { Start-Sleep -Seconds 2; break }

                        # 1. Flush DNS & ARP table
                        Write-Host "      [1/4] Flushing DNS cache and clearing ARP tables..." -ForegroundColor Gray
                        Clear-DnsClientCache -ErrorAction SilentlyContinue
                        ipconfig /flushdns >$null 2>&1
                        arp -d * >$null 2>&1

                        # 2. Reset Winsock & TCP/IP stack without forcing global TCP tuning
                        Write-Host "      [2/4] Resetting Winsock and TCP/IP stack..." -ForegroundColor Gray
                        netsh winsock reset >$null 2>&1
                        $winsockExit = $LASTEXITCODE
                        netsh int ip reset >$null 2>&1
                        $ipResetExit = $LASTEXITCODE

                        # 3. Restart required client services
                        Write-Host "      [3/4] Restarting DHCP and DNS Client services..." -ForegroundColor Gray
                        Set-Service -Name Dhcp -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name Dhcp -ErrorAction SilentlyContinue
                        Set-Service -Name Dnscache -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name Dnscache -ErrorAction SilentlyContinue

                        # 4. Renew only when the selected adapter already uses DHCP
                        Write-Host "      [4/4] Refreshing and validating the selected adapter..." -ForegroundColor Gray
                        $targetIPv4Interface = Get-NetIPInterface -InterfaceIndex $targetAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                        if ($targetIPv4Interface.Dhcp -eq 'Enabled') {
                            ipconfig /renew "$($targetAdapter.Name)" >$null 2>&1
                        } else {
                            Write-Host "      [INFO] $($targetAdapter.Name) uses a static IPv4 address; DHCP renew skipped." -ForegroundColor DarkYellow
                        }
                        $validIPv4 = Get-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '0.0.0.0' }

                        if ($winsockExit -eq 0 -and $ipResetExit -eq 0 -and $validIPv4) {
                            Write-Host "`n[OK] Network stack reset completed. A reboot is recommended." -ForegroundColor Green
                            Write-Host "     Current IPv4: $($validIPv4.IPAddress -join ', ')" -ForegroundColor Cyan
                        } else {
                            Write-Host "`n[WARNING] Reset completed, but IPv4 validation failed or a reset command returned an error." -ForegroundColor Yellow
                            Write-Host "          Run option [7] before making further changes." -ForegroundColor Yellow
                        }
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        Write-Host "`nRepairing DHCP Client, DNS Cache Services & Stale Leases..." -ForegroundColor Yellow

                        $targetAdapter = Select-ToolkitPhysicalAdapter -Prompt 'Choose the adapter that should use DHCP'
                        if (-not $targetAdapter) { Start-Sleep -Seconds 2; break }
                        
                        # 1. Restart DHCP and DNS services
                        Write-Host "      [1/4] Starting and configuring DHCP & DNS Client services..." -ForegroundColor Gray
                        Set-Service -Name Dhcp -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name Dhcp -ErrorAction SilentlyContinue
                        Set-Service -Name Dnscache -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name Dnscache -ErrorAction SilentlyContinue

                        # 2. Reset only the selected physical interface to DHCP
                        Write-Host "      [2/4] Resetting $($targetAdapter.Name) IP and DNS assignments to DHCP..." -ForegroundColor Gray
                        netsh interface ipv4 set address name="$($targetAdapter.Name)" source=dhcp >$null 2>&1
                        $addressExit = $LASTEXITCODE
                        Set-DnsClientServerAddress -InterfaceIndex $targetAdapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue

                        # 3. Flush & Release
                        Write-Host "      [3/4] Releasing IP lease and flushing routing cache..." -ForegroundColor Gray
                        ipconfig /release "$($targetAdapter.Name)" >$null 2>&1
                        ipconfig /flushdns >$null 2>&1

                        # 4. Renew
                        Write-Host "      [4/4] Requesting new IP lease from Gateway/DHCP Server..." -ForegroundColor Gray
                        ipconfig /renew "$($targetAdapter.Name)" >$null 2>&1
                        Start-Sleep -Seconds 1
                        $dhcpAddress = Get-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -in @('Dhcp', 'RouterAdvertisement') } |
                            Select-Object -First 1
                        $defaultGateway = (Get-NetIPConfiguration -InterfaceIndex $targetAdapter.ifIndex -ErrorAction SilentlyContinue).IPv4DefaultGateway.NextHop

                        if ($addressExit -eq 0 -and $dhcpAddress -and $defaultGateway) {
                            Write-Host "`n[OK] DHCP lease verified: $($dhcpAddress.IPAddress), gateway $defaultGateway" -ForegroundColor Green
                        } else {
                            $currentAddress = (Get-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ', '
                            Write-Host "`n[ERROR] DHCP validation failed. Current IPv4: $currentAddress" -ForegroundColor Red
                            Write-Host "        Run option [7] and check the DHCP server/AP path before using netcfg -d." -ForegroundColor Yellow
                        }
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        Write-Host "`nExecuting Deep Factory Network Reset (netcfg -d)..." -ForegroundColor Yellow
                        Write-Host "      [Warning] This will purge all corrupt virtual adapters, VPN/Antivirus network filters," -ForegroundColor Gray
                        Write-Host "      and reset the entire Windows NDIS network stack to factory condition." -ForegroundColor Gray
                        
                        Write-Host "      VPN clients, virtual switches and security filters may need reinstalling." -ForegroundColor Red
                        $deepConfirm = Read-Host "Type RESET to continue"
                        if ($deepConfirm -cne 'RESET') {
                            Write-Host '[INFO] Deep reset cancelled.' -ForegroundColor Yellow
                            Start-Sleep -Seconds 1
                            break
                        }

                        $inventoryPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "NETWORK_ADAPTERS_BEFORE_NETCFG_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
                        Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
                            Format-Table Name, InterfaceDescription, Status, MacAddress, LinkSpeed -AutoSize |
                            Out-String | Out-File -LiteralPath $inventoryPath -Encoding utf8
                        netcfg -d
                        $netcfgExit = $LASTEXITCODE

                        if ($netcfgExit -eq 0) {
                            Write-Host "`n[OK] Deep factory reset executed. REBOOT is required." -ForegroundColor Green
                            Write-Host "     Adapter inventory: $inventoryPath" -ForegroundColor Cyan
                        } else {
                            Write-Host "`n[ERROR] netcfg -d returned exit code $netcfgExit. No success is being assumed." -ForegroundColor Red
                        }
                        Write-Host "`nPress Enter to return..." -ForegroundColor Yellow
                        Read-Host | Out-Null
                    }
                    "4" {
                        Write-Host "`nRestoring Hosts file to Windows Factory Default..." -ForegroundColor Yellow
                        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                        Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                        
                        $cleanHosts = @"
# Copyright (c) 1993-2009 Microsoft Corp.
#
# Default Windows Hosts File
127.0.0.1       localhost
::1             localhost
"@
                        $cleanHosts | Set-Content -Path $hostsPath -Encoding ascii -Force
                        Clear-DnsClientCache -ErrorAction SilentlyContinue
                        ipconfig /flushdns >$null 2>&1
                        
                        Write-Host "[OK] Hosts file has been reset to default clean state." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "5" {
                        Write-Host "`n=== Set Static Diagnostic IP ===" -ForegroundColor Yellow
                        Write-Host "Use an address reserved for this device and outside the DHCP pool." -ForegroundColor Gray
                        $activeAdapter = Select-ToolkitPhysicalAdapter -Prompt 'Choose the adapter for the temporary static IPv4 address'
                        if (-not $activeAdapter) { Start-Sleep -Seconds 2; break }

                        $ipInput = Read-Host "Enter Static IPv4 Address (required; no automatic default)"
                        $gwInput = Read-Host "Enter Gateway IP Address (default: 192.168.10.1)"
                        if ([string]::IsNullOrWhiteSpace($gwInput)) { $gwInput = "192.168.10.1" }
                        $maskInput = Read-Host "Enter Subnet Mask (default: 255.255.255.0)"
                        if ([string]::IsNullOrWhiteSpace($maskInput)) { $maskInput = '255.255.255.0' }
                        $dnsInput = Read-Host "Enter comma-separated DNS servers (default: $gwInput, 8.8.8.8)"
                        if ([string]::IsNullOrWhiteSpace($dnsInput)) { $dnsInput = "$gwInput,8.8.8.8" }
                        $dnsServers = @($dnsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

                        $invalidDns = @($dnsServers | Where-Object { -not (Test-ToolkitIPv4Address $_) })
                        if (-not (Test-ToolkitIPv4Address $ipInput) -or
                            -not (Test-ToolkitIPv4Address $gwInput) -or
                            -not (Test-ToolkitIPv4Address $maskInput) -or
                            $invalidDns.Count -gt 0) {
                            Write-Host '[ERROR] One or more IPv4, gateway, subnet-mask or DNS values are invalid.' -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            break
                        }

                        $existingAddress = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -eq $ipInput -and $_.InterfaceIndex -ne $activeAdapter.ifIndex }
                        $respondsToPing = Test-Connection -ComputerName $ipInput -Count 1 -Quiet -ErrorAction SilentlyContinue
                        if ($existingAddress -or $respondsToPing) {
                            Write-Host "[ERROR] $ipInput is already configured locally or responded to ping. Static assignment cancelled." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            break
                        }

                        $backupPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "NETWORK_BEFORE_STATIC_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
                        Get-NetIPConfiguration -InterfaceIndex $activeAdapter.ifIndex -Detailed -ErrorAction SilentlyContinue |
                            Format-List * | Out-String | Out-File -LiteralPath $backupPath -Encoding utf8

                        netsh interface ipv4 set address name="$($activeAdapter.Name)" source=static address=$ipInput mask=$maskInput gateway=$gwInput store=persistent >$null 2>&1
                        $staticExit = $LASTEXITCODE
                        if ($staticExit -eq 0) {
                            Set-DnsClientServerAddress -InterfaceIndex $activeAdapter.ifIndex -ServerAddresses $dnsServers -ErrorAction SilentlyContinue
                            $appliedAddress = Get-NetIPAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                                Where-Object { $_.IPAddress -eq $ipInput }
                            if ($appliedAddress) {
                                Write-Host "`n[OK] Static IP $ipInput applied to $($activeAdapter.Name)." -ForegroundColor Green
                                Write-Host "     Previous configuration: $backupPath" -ForegroundColor Cyan
                            } else {
                                Write-Host "`n[ERROR] netsh returned success, but the requested IP was not found on the adapter." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "`n[ERROR] Static IPv4 assignment failed with exit code $staticExit." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "6" {
                        Write-Host "`nRestoring one physical adapter to Dynamic IP (DHCP)..." -ForegroundColor Yellow
                        $targetAdapter = Select-ToolkitPhysicalAdapter -Prompt 'Choose the physical adapter to restore to DHCP'
                        if (-not $targetAdapter) { Start-Sleep -Seconds 2; break }

                        netsh interface ipv4 set address name="$($targetAdapter.Name)" source=dhcp >$null 2>&1
                        $dhcpRestoreExit = $LASTEXITCODE
                        Set-DnsClientServerAddress -InterfaceIndex $targetAdapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                        ipconfig /renew "$($targetAdapter.Name)" >$null 2>&1
                        Start-Sleep -Seconds 1
                        $restoredAddress = Get-NetIPAddress -InterfaceIndex $targetAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -eq 'Dhcp' } |
                            Select-Object -First 1
                        if ($dhcpRestoreExit -eq 0 -and $restoredAddress) {
                            Write-Host "[OK] $($targetAdapter.Name) restored to DHCP: $($restoredAddress.IPAddress)" -ForegroundColor Green
                        } else {
                            Write-Host "[ERROR] DHCP restore did not produce a valid lease on $($targetAdapter.Name)." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "7" {
                        Write-Host "`nGathering Comprehensive Network Diagnostics & Event Logs..." -ForegroundColor Yellow
                        
                        $desktopPath = [Environment]::GetFolderPath("Desktop")
                        $reportFile = "$desktopPath\NETWORK_DIAGNOSTIC_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

                        $report = New-Object System.Text.StringBuilder
                        [void]$report.AppendLine("=========================================================================")
                        [void]$report.AppendLine("         WINDOWS NETWORK & DHCP DIAGNOSTIC REPORT                        ")
                        [void]$report.AppendLine("=========================================================================")
                        [void]$report.AppendLine("Generated On   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
                        [void]$report.AppendLine("Computer Name  : $env:COMPUTERNAME")
                        [void]$report.AppendLine("OS Version     : $((Get-CimInstance Win32_OperatingSystem).Caption) ($((Get-CimInstance Win32_OperatingSystem).Version))")
                        [void]$report.AppendLine("=========================================================================`n")

                        # 1. Physical & Wireless Network Adapters
                        [void]$report.AppendLine("--- [1] NETWORK ADAPTER STATUS & HARDWARE ---")
                        try {
                            $adapters = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Format-Table Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion -AutoSize | Out-String
                            [void]$report.AppendLine($adapters)
                        } catch { [void]$report.AppendLine("Error querying NetAdapter: $_") }

                        # 2. IP Configuration Details
                        [void]$report.AppendLine("`n--- [2] IPCONFIG /ALL OUTPUT ---")
                        try {
                            $ipAll = (ipconfig /all | Out-String)
                            [void]$report.AppendLine($ipAll)
                        } catch { [void]$report.AppendLine("Error running ipconfig: $_") }

                        # 3. Wi-Fi Connection & Signal Details
                        [void]$report.AppendLine("`n--- [3] WI-FI INTERFACE & SSID STATUS ---")
                        try {
                            $wlanStatus = (netsh wlan show interfaces | Out-String)
                            [void]$report.AppendLine($wlanStatus)
                            $wlanDrivers = (netsh wlan show drivers | Out-String)
                            [void]$report.AppendLine($wlanDrivers)
                        } catch { [void]$report.AppendLine("Error querying Wi-Fi interfaces: $_") }

                        # 4. Critical Networking Windows Services
                        [void]$report.AppendLine("`n--- [4] CRITICAL NETWORK SERVICES STATUS ---")
                        $services = @("Dhcp", "Dnscache", "WlanSvc", "dot3svc", "LanmanWorkstation", "NlaSvc", "netprofm", "wuauserv")
                        foreach ($svc in $services) {
                            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                            if ($s) {
                                [void]$report.AppendLine(("{0,-20} : Status={1,-10} Startup={2}" -f $s.Name, $s.Status, $s.StartType))
                            } else {
                                [void]$report.AppendLine(("{0,-20} : NOT FOUND" -f $svc))
                            }
                        }

                        # 5. Network Stack Filter Drivers (NDIS Lightweight Filters)
                        [void]$report.AppendLine("`n--- [5] NDIS NETWORK FILTER DRIVERS (Antivirus/VPN/Virtual) ---")
                        try {
                            $ndisFilters = Get-NetAdapterBinding -AllBindings -ErrorAction Stop | Sort-Object Name, ComponentId | Format-Table Name, DisplayName, ComponentId, Enabled -AutoSize | Out-String
                            [void]$report.AppendLine($ndisFilters)
                        } catch { [void]$report.AppendLine("Error querying NDIS filters: $_") }

                        # 6. Gateway & DNS Ping Connectivity Test
                        [void]$report.AppendLine("`n--- [6] CONNECTIVITY & GATEWAY REACHABILITY TEST ---")
                        $defaultGateways = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                            Sort-Object RouteMetric | Select-Object -ExpandProperty NextHop -Unique)
                        $testTargets = @($defaultGateways + @('8.8.8.8', '1.1.1.1') | Where-Object { $_ } | Select-Object -Unique)
                        foreach ($t in $testTargets) {
                            $ping = Test-Connection -ComputerName $t -Count 2 -Quiet -ErrorAction SilentlyContinue
                            [void]$report.AppendLine("Ping target $t : $(if ($ping) { 'SUCCESS' } else { 'FAILED' })")
                        }

                        # 7. Hosts File Content
                        [void]$report.AppendLine("`n--- [7] CURRENT HOSTS FILE CONTENT ---")
                        try {
                            $hosts = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue | Out-String
                            [void]$report.AppendLine($hosts)
                        } catch { [void]$report.AppendLine("Error reading hosts file: $_") }

                        # 8. Recent DHCP Client Event Logs
                        [void]$report.AppendLine("`n--- [8] RECENT DHCP CLIENT EVENT LOGS (Admin + Operational) ---")
                        foreach ($dhcpLogName in @('Microsoft-Windows-Dhcp-Client/Admin', 'Microsoft-Windows-Dhcp-Client/Operational')) {
                            [void]$report.AppendLine("Log: $dhcpLogName")
                            try {
                                $dhcpLogs = Get-WinEvent -LogName $dhcpLogName -MaxEvents 15 -ErrorAction Stop |
                                    Format-List TimeCreated, Id, LevelDisplayName, Message | Out-String
                                if ($dhcpLogs) { [void]$report.AppendLine($dhcpLogs) }
                                else { [void]$report.AppendLine('No recent events logged.') }
                            } catch {
                                [void]$report.AppendLine("Unavailable or disabled: $($_.Exception.Message)")
                            }
                        }

                        # 9. Recent System WLAN-AutoConfig Event Logs
                        [void]$report.AppendLine("`n--- [9] RECENT SYSTEM NETWORK & WLAN ERRORS (Last 10 Events) ---")
                        try {
                            $sysLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=@('Microsoft-Windows-WLAN-AutoConfig', 'Microsoft-Windows-DHCP-Client'); Level=1,2,3} -MaxEvents 10 -ErrorAction SilentlyContinue | Format-Table TimeCreated, ProviderName, Id, LevelDisplayName, Message -AutoSize | Out-String
                            if ($sysLogs) {
                                [void]$report.AppendLine($sysLogs)
                            } else {
                                [void]$report.AppendLine("No recent System network error events found.")
                            }
                        } catch { [void]$report.AppendLine("System Log query: $_") }

                        [void]$report.AppendLine("`n=========================================================================")
                        [void]$report.AppendLine("                             END OF REPORT                               ")
                        [void]$report.AppendLine("=========================================================================")

                        # Save report file to Desktop
                        $report.ToString() | Out-File -FilePath $reportFile -Encoding utf8 -Force
                        Write-Host "   [OK] Diagnostic report saved to Desktop:" -ForegroundColor Green
                        Write-Host "        $reportFile" -ForegroundColor Cyan

                        # Copy to removable drives only after explicit consent.
                        $removableDrives = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter })
                        if ($removableDrives.Count -gt 0) {
                            $copyToUsb = Read-Host 'Copy this potentially sensitive report to connected removable drive(s)? (Y/N)'
                            if ($copyToUsb -match '(?i)^y(es)?$') {
                                foreach ($drive in $removableDrives) {
                                    $usbFile = "$($drive.DriveLetter):\NETWORK_DIAGNOSTIC_$($env:COMPUTERNAME).txt"
                                    $report.ToString() | Out-File -FilePath $usbFile -Encoding utf8 -Force
                                    Write-Host "   [OK] Diagnostic report copied to: $usbFile" -ForegroundColor Green
                                }
                            }
                        }

                        Write-Host "`nSilakan buka atau periksa file teks tersebut untuk melihat hasil diagnosa lengkap." -ForegroundColor Yellow
                        Write-Host "`nPress Enter to return..." -ForegroundColor Gray
                        Read-Host | Out-Null
                    }
                    "0" { break }
                }
            }
        }
        "6" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "                    WINDOWS AUTO-UPDATE MANAGER                          " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   [1] Pause Windows Auto-Update for 9999 Days (~27 Years)" -ForegroundColor Red
                Write-Host "   [2] Resume / Restore Windows Auto-Update" -ForegroundColor Green
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                $updateChoice = Read-Host "Select option (0-2)"

                if ($updateChoice -eq "0") {
                    break
                } elseif ($updateChoice -eq "1") {
                    Write-Host "`nPausing Windows Auto-Update for 9999 Days (~27 Years)..." -ForegroundColor Yellow
                    
                    # 1. Clean up old GPO registry blocks that cause "Something went wrong" UI errors
                    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f >$null 2>&1
                    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f >$null 2>&1

                    # 2. Ensure services are running so Windows Update Settings page opens cleanly
                    $updateServices = @("wuauserv", "UsoSvc", "dosvc")
                    foreach ($svcName in $updateServices) {
                        if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
                            Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
                            Start-Service -Name $svcName -ErrorAction SilentlyContinue
                        }
                    }

                    # 3. Set 9999-day pause expiry dates in Windows Update UX Settings & Policy keys
                    $now = Get-Date
                    $futureDate = $now.AddDays(9999)
                    $pauseStart = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $pauseEnd = $futureDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

                    $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                    if (-not (Test-Path $uxPath)) { New-Item -Path $uxPath -Force | Out-Null }

                    Set-ItemProperty -Path $uxPath -Name "PauseUpdatesStartTime" -Value $pauseStart -Force
                    Set-ItemProperty -Path $uxPath -Name "PauseUpdatesExpiryTime" -Value $pauseEnd -Force
                    Set-ItemProperty -Path $uxPath -Name "PauseFeatureUpdatesStartTime" -Value $pauseStart -Force
                    Set-ItemProperty -Path $uxPath -Name "PauseFeatureUpdatesExpiryTime" -Value $pauseEnd -Force
                    Set-ItemProperty -Path $uxPath -Name "PauseQualityUpdatesStartTime" -Value $pauseStart -Force
                    Set-ItemProperty -Path $uxPath -Name "PauseQualityUpdatesExpiryTime" -Value $pauseEnd -Force

                    $polPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                    if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }

                    Set-ItemProperty -Path $polPath -Name "PauseFeatureUpdatesStartTime" -Value $pauseStart -Force
                    Set-ItemProperty -Path $polPath -Name "PauseFeatureUpdatesEndTime" -Value $pauseEnd -Force
                    Set-ItemProperty -Path $polPath -Name "PauseQualityUpdatesStartTime" -Value $pauseStart -Force
                    Set-ItemProperty -Path $polPath -Name "PauseQualityUpdatesEndTime" -Value $pauseEnd -Force

                    Write-Host "      [OK] Services enabled & GPO blocks cleared." -ForegroundColor Gray
                    Write-Host "      [OK] Pause start time : $($now.ToString('dd MMMM yyyy'))" -ForegroundColor Gray
                    Write-Host "      [OK] Pause expiry date: $($futureDate.ToString('dd MMMM yyyy')) (Calculated 9999 days dynamically)" -ForegroundColor Gray
                    Write-Host "`n[OK] Windows Auto-Update paused dynamically for 9999 days (until $($futureDate.ToString('dd MMMM yyyy')))." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                } elseif ($updateChoice -eq "2") {
                    Write-Host "`nResuming Windows Auto-Update..." -ForegroundColor Yellow
                    
                    # 1. Remove pause timestamps
                    $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                    $pauseKeys = @("PauseUpdatesStartTime", "PauseUpdatesExpiryTime", "PauseFeatureUpdatesStartTime", "PauseFeatureUpdatesExpiryTime", "PauseQualityUpdatesStartTime", "PauseQualityUpdatesExpiryTime")
                    foreach ($k in $pauseKeys) {
                        Remove-ItemProperty -Path $uxPath -Name $k -ErrorAction SilentlyContinue
                    }

                    $polPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                    $polKeys = @("PauseFeatureUpdatesStartTime", "PauseFeatureUpdatesEndTime", "PauseQualityUpdatesStartTime", "PauseQualityUpdatesEndTime")
                    foreach ($k in $polKeys) {
                        Remove-ItemProperty -Path $polPath -Name $k -ErrorAction SilentlyContinue
                    }

                    # 2. Clean up GPO blocks
                    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f >$null 2>&1
                    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f >$null 2>&1

                    # 3. Ensure services are running
                    $updateServices = @("wuauserv", "UsoSvc", "dosvc")
                    foreach ($svcName in $updateServices) {
                        if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
                            Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
                            Start-Service -Name $svcName -ErrorAction SilentlyContinue
                        }
                    }

                    Write-Host "`n[OK] Windows Auto-Update resumed successfully." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "`n[WARN] Invalid choice. No changes were made." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }
        }
        "7" {
            Write-Host "`nFixing Lansweeper Access & Installing LsAgent..." -ForegroundColor Yellow
            
            # 0. Single Prompt for Device Identity / Hostname (e.g. BERSA-DOK-HRGA or RIADTHON-DOK-REPAIRMAINTENANCE)
            $inputIdentity = Read-Host "Enter Device Hostname (e.g. BERSA-DOK-HRGA) [Press Enter to skip]"

            if ($inputIdentity) {
                $cleanDescription = ($inputIdentity -replace '[^a-zA-Z0-9-]', '').ToUpper()
                $cleanHostname = $cleanDescription
                if ($cleanHostname.Length -gt 15) {
                    if ($cleanDescription -match '^(.*?-DOK)') {
                        $cleanHostname = $Matches[1]
                    } else {
                        $cleanHostname = $cleanHostname.Substring(0, 15)
                    }
                }

                Rename-Computer -NewName $cleanHostname -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters" -Name "srvcomment" -Value $cleanDescription -ErrorAction SilentlyContinue

                Write-Host "      [OK] Hostname set to: $cleanHostname (Description: $cleanDescription)" -ForegroundColor Green
            }

            # 1. Create or update local admin account for remote deployment
            $deployUser = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LOCAL_ADMIN_USER')
            if ([string]::IsNullOrWhiteSpace($deployUser)) { $deployUser = 'AsetDP' }
            $localAdminPasswordText = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LOCAL_ADMIN_PASSWORD')
            if ([string]::IsNullOrWhiteSpace($localAdminPasswordText)) {
                $localAdminPasswordText = '@AsetDP25'
            }
            $deployPass = ConvertTo-SecureString $localAdminPasswordText -AsPlainText -Force
            if (-not (Get-LocalUser -Name $deployUser -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $deployUser -Password $deployPass -PasswordNeverExpires -AccountNeverExpires -ErrorAction SilentlyContinue | Out-Null
                Add-LocalGroupMember -Group "Administrators" -Member $deployUser -ErrorAction SilentlyContinue
                Write-Host "      [OK] Local admin account '$deployUser' created for remote management." -ForegroundColor Green
            } else {
                Set-LocalUser -Name $deployUser -Password $deployPass -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                Write-Host "      [OK] Local admin account '$deployUser' already exists. Password updated." -ForegroundColor Green
            }

            # 2. Enable Firewall Rules, Services & Remote UAC (LocalAccountTokenFilterPolicy)
            reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f >$null 2>&1
            netsh advfirewall firewall set rule group="remote administration" new enable=yes >$null 2>&1
            netsh advfirewall firewall set rule group="windows management instrumentation (wmi)" new enable=yes >$null 2>&1
            netsh advfirewall firewall set rule group="file and printer sharing" new enable=yes >$null 2>&1
            Set-Service -Name RemoteRegistry -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name RemoteRegistry -ErrorAction SilentlyContinue
            Set-Service -Name winmgmt -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name winmgmt -ErrorAction SilentlyContinue
            Write-Host "      [OK] WMI, RPC, Remote UAC, Remote Registry and administration rules enabled." -ForegroundColor Green

            # 2. Silent Install LsAgent if present
            $localLsAgent1 = "D:\Sharing\Software\LsAgent-windows.exe"
            $localLsAgent2 = "C:\Program Files (x86)\Lansweeper\Client\LsAgent-windows.exe"
            $uncLsAgent1   = $null
            $uncLsAgent2   = $null
            # Direct-LAN mode does not require a Cloud Relay key. If an optional
            # relay key is supplied through the environment, add it as fallback.
            $agentArgs     = '--mode unattended --server 192.168.10.160 --port 9524'
            $agentKey      = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LSAGENT_KEY')
            if (-not [string]::IsNullOrWhiteSpace($agentKey)) {
                $agentArgs += " --agentkey $agentKey"
                Write-Host '      [INFO] Cloud Relay fallback enabled from IT_TOOLKIT_LSAGENT_KEY.' -ForegroundColor Gray
            }

            # Check connected Flash Drives (USB)
            $fdLsAgent = $null
            $removableDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
            foreach ($drive in $removableDrives) {
                $candidate1 = "$($drive):\Software\LsAgent-windows.exe"
                $candidate2 = "$($drive):\soft\LsAgent-windows.exe"
                $candidate3 = "$($drive):\LsAgent-windows.exe"
                if (Test-Path $candidate1) { $fdLsAgent = $candidate1; break }
                if (Test-Path $candidate2) { $fdLsAgent = $candidate2; break }
                if (Test-Path $candidate3) { $fdLsAgent = $candidate3; break }
            }

            # Connect only when no local/USB installer is available. Credentials are
            # prompted or read from environment variables and are never embedded here.
            if (-not $fdLsAgent -and -not (Test-Path $localLsAgent1) -and -not (Test-Path $localLsAgent2)) {
                if (Connect-ToolkitDeploymentShare -Name 'ToolkitShare' -Root '\\192.168.10.160\Sharing') {
                    $uncLsAgent1 = 'ToolkitShare:\Software\LsAgent-windows.exe'
                }
                if (Connect-ToolkitDeploymentShare -Name 'ToolkitPackage' -Root '\\192.168.10.160\DefaultPackageShare$') {
                    $uncLsAgent2 = 'ToolkitPackage:\Client\LsAgent-windows.exe'
                }
            }

            if ($fdLsAgent) {
                Write-Host "      [Flash Drive] Found installer on USB ($fdLsAgent). Installing silently..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $fdLsAgent -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully from USB." -ForegroundColor Green
            } elseif (Test-Path $localLsAgent1) {
                Write-Host "      [Local] Installing LsAgent silently..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $localLsAgent1 -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully." -ForegroundColor Green
            } elseif (Test-Path $localLsAgent2) {
                Write-Host "      [Local] Installing LsAgent silently..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $localLsAgent2 -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully." -ForegroundColor Green
            } elseif ($uncLsAgent1 -and (Test-Path $uncLsAgent1)) {
                Write-Host "      [Network Share] Installing LsAgent silently via network share..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $uncLsAgent1 -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully via network share." -ForegroundColor Green
            } elseif ($uncLsAgent2 -and (Test-Path $uncLsAgent2)) {
                Write-Host "      [Network Share] Installing LsAgent silently via network share..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $uncLsAgent2 -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully via network share." -ForegroundColor Green
            } else {
                Write-Host "      [INFO] LsAgent installer not found on USB or network share; firewall/RPC rules configured." -ForegroundColor Yellow
            }

            Write-Host "`n[OK] Lansweeper configuration completed successfully." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "8" {
            Write-Host "`nInstalling Kaspersky Endpoint Security 14.0..." -ForegroundColor Yellow
            
            # 0. Single Prompt for Device Identity / Hostname (e.g. BERSA-DOK-HRGA or RIADTHON-DOK-REPAIRMAINTENANCE)
            $inputIdentity = Read-Host "Enter Device Hostname (e.g. BERSA-DOK-HRGA) [Press Enter to skip]"

            if ($inputIdentity) {
                $cleanDescription = ($inputIdentity -replace '[^a-zA-Z0-9-]', '').ToUpper()
                $cleanHostname = $cleanDescription
                if ($cleanHostname.Length -gt 15) {
                    if ($cleanDescription -match '^(.*?-DOK)') {
                        $cleanHostname = $Matches[1]
                    } else {
                        $cleanHostname = $cleanHostname.Substring(0, 15)
                    }
                }

                Rename-Computer -NewName $cleanHostname -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters" -Name "srvcomment" -Value $cleanDescription -ErrorAction SilentlyContinue

                Write-Host "      [OK] Hostname set to: $cleanHostname (Description: $cleanDescription)" -ForegroundColor Green
            }

            Write-Host "`nSelect Installer Source:" -ForegroundColor Cyan
            Write-Host "   [1] Auto-Detect (Flash Drive -> Local Disk -> Network Share)"
            Write-Host "   [2] Flash Drive (USB)"
            Write-Host "   [3] Local Disk (D:\Sharing\Software)"
            Write-Host "   [4] Network Share (\\192.168.10.160\Sharing\Software)"
            Write-Host "   [0] Cancel / Back to Main Menu" -ForegroundColor Red
            $sourceChoice = Read-Host "Select source (0-4) [Default: 1]"
            if ($sourceChoice -eq "0") {
                continue
            }
            if (-not $sourceChoice) { $sourceChoice = "1" }

            # 0. Deep Clean Incompatible Antivirus Remnants from WMI, Services & Registry
            Write-Host "      [Cleaning] Purging leftover third-party Antivirus remnants (360, AVG, Avast, Smadav, McAfee, Norton, Bitdefender, ESET, Malwarebytes, Avira, Sophos, TrendMicro, Webroot)..." -ForegroundColor Gray
            
            # Stop and remove leftover services
            $avPatterns = @(
                '*360*', '*Qihu*', '*ZhuDong*', '*AVG*', '*Avast*', '*Smadav*', '*McAfee*', '*Norton*', '*Symantec*',
                '*Bitdefender*', '*ESET*', '*ekrn*', '*Malwarebytes*', '*MBAM*', '*Avira*', '*Sophos*', '*TrendMicro*',
                '*Webroot*', '*WRSA*', '*Panda*', '*Baidu*', '*PCMatic*', '*BullGuard*', '*F-Secure*', '*Cylance*',
                '*SentinelOne*', '*TotalAV*', '*K7AntiVirus*', '*RAV*', '*Reason*'
            )
            Get-Service | Where-Object { 
                $name = $_.Name; $disp = $_.DisplayName
                ($avPatterns | Where-Object { $name -like $_ -or $disp -like $_ })
            } | ForEach-Object {
                Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
                sc.exe delete $_.Name >$null 2>&1
            }

            # Unregister non-Microsoft & non-Kaspersky products from Windows Security Center WMI
            try {
                Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntivirusProduct" -ErrorAction SilentlyContinue | 
                Where-Object { $_.displayName -notlike "*Defender*" -and $_.displayName -notlike "*Kaspersky*" } | 
                Remove-CimInstance -ErrorAction SilentlyContinue
            } catch {}

            # Remove leftover legacy registry keys
            $oldAvRegs = @(
                "HKLM:\SOFTWARE\360Safe", "HKLM:\SOFTWARE\WOW6432Node\360Safe",
                "HKLM:\SOFTWARE\Qihoo", "HKLM:\SOFTWARE\WOW6432Node\Qihoo",
                "HKLM:\SOFTWARE\AVG", "HKLM:\SOFTWARE\WOW6432Node\AVG",
                "HKLM:\SOFTWARE\Avast Software", "HKLM:\SOFTWARE\WOW6432Node\Avast Software",
                "HKLM:\SOFTWARE\Smadav", "HKLM:\SOFTWARE\WOW6432Node\Smadav",
                "HKLM:\SOFTWARE\McAfee", "HKLM:\SOFTWARE\WOW6432Node\McAfee",
                "HKLM:\SOFTWARE\Norton", "HKLM:\SOFTWARE\WOW6432Node\Norton",
                "HKLM:\SOFTWARE\Symantec", "HKLM:\SOFTWARE\WOW6432Node\Symantec",
                "HKLM:\SOFTWARE\Bitdefender", "HKLM:\SOFTWARE\WOW6432Node\Bitdefender",
                "HKLM:\SOFTWARE\ESET", "HKLM:\SOFTWARE\WOW6432Node\ESET",
                "HKLM:\SOFTWARE\Malwarebytes", "HKLM:\SOFTWARE\WOW6432Node\Malwarebytes",
                "HKLM:\SOFTWARE\Avira", "HKLM:\SOFTWARE\WOW6432Node\Avira",
                "HKLM:\SOFTWARE\Sophos", "HKLM:\SOFTWARE\WOW6432Node\Sophos",
                "HKLM:\SOFTWARE\TrendMicro", "HKLM:\SOFTWARE\WOW6432Node\TrendMicro",
                "HKLM:\SOFTWARE\WRSA", "HKLM:\SOFTWARE\WOW6432Node\WRSA",
                "HKLM:\SOFTWARE\Panda Software", "HKLM:\SOFTWARE\WOW6432Node\Panda Software",
                "HKLM:\SOFTWARE\BaiduSecurity", "HKLM:\SOFTWARE\WOW6432Node\BaiduSecurity",
                "HKLM:\SOFTWARE\BullGuard", "HKLM:\SOFTWARE\WOW6432Node\BullGuard",
                "HKLM:\SOFTWARE\F-Secure", "HKLM:\SOFTWARE\WOW6432Node\F-Secure",
                "HKLM:\SOFTWARE\Cylance", "HKLM:\SOFTWARE\WOW6432Node\Cylance",
                "HKLM:\SOFTWARE\SentinelOne", "HKLM:\SOFTWARE\WOW6432Node\SentinelOne",
                "HKLM:\SOFTWARE\TotalAV", "HKLM:\SOFTWARE\WOW6432Node\TotalAV",
                "HKLM:\SOFTWARE\RAV", "HKLM:\SOFTWARE\WOW6432Node\RAV",
                "HKLM:\SOFTWARE\Reason Labs", "HKLM:\SOFTWARE\WOW6432Node\Reason Labs",
                "HKLM:\SOFTWARE\Reason Cybersecurity", "HKLM:\SOFTWARE\WOW6432Node\Reason Cybersecurity"
            )
            foreach ($rPath in $oldAvRegs) {
                if (Test-Path $rPath) { Remove-Item -Path $rPath -Recurse -Force -ErrorAction SilentlyContinue }
            }

            $localInstaller = "D:\Sharing\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
            $uncInstaller   = $null
            $kesArgs        = ""

            # Check connected Flash Drives (USB)
            $fdInstaller = $null
            $removableDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter
            foreach ($drive in $removableDrives) {
                $c1 = "$($drive):\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
                $c2 = "$($drive):\soft\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
                $c3 = "$($drive):\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
                    if (Test-Path $c1) { $fdInstaller = $c1; break }
                if (Test-Path $c2) { $fdInstaller = $c2; break }
                if (Test-Path $c3) { $fdInstaller = $c3; break }
            }

            $networkSourceNeeded = $sourceChoice -eq '4' -or
                ($sourceChoice -eq '1' -and -not $fdInstaller -and -not (Test-Path $localInstaller))
            if ($networkSourceNeeded -and (Connect-ToolkitDeploymentShare -Name 'ToolkitShare' -Root '\\192.168.10.160\Sharing')) {
                $uncInstaller = 'ToolkitShare:\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe'
            }

            $tempInstaller = "$env:SystemDrive\Temp\KES14_Setup.exe"
            if (-not (Test-Path "$env:SystemDrive\Temp")) { New-Item -Path "$env:SystemDrive\Temp" -ItemType Directory -Force | Out-Null }

            $targetInstallerToRun = $null

            switch ($sourceChoice) {
                "2" {
                    if ($fdInstaller) {
                        Write-Host "      [Flash Drive] Copying installer from USB to Local Disk ($tempInstaller)..." -ForegroundColor Gray
                        Copy-Item -Path $fdInstaller -Destination $tempInstaller -Force -ErrorAction SilentlyContinue
                        if (Test-Path $tempInstaller) {
                            $targetInstallerToRun = $tempInstaller
                            Write-Host "      [OK] Copied to Local Disk. You can now safely EJECT your Flash Drive (USB)!" -ForegroundColor Green
                        } else {
                            $targetInstallerToRun = $fdInstaller
                        }
                    } else {
                        Write-Host "      [ERROR] Installer not found on any connected Flash Drive (USB)." -ForegroundColor Red
                    }
                }
                "3" {
                    if (Test-Path $localInstaller) {
                        if ($localInstaller -ne $tempInstaller) {
                            Write-Host "      [Local Disk] Copying installer to Local Temp ($tempInstaller)..." -ForegroundColor Gray
                            Copy-Item -Path $localInstaller -Destination $tempInstaller -Force -ErrorAction SilentlyContinue
                            if (Test-Path $tempInstaller) { $targetInstallerToRun = $tempInstaller } else { $targetInstallerToRun = $localInstaller }
                        } else {
                            $targetInstallerToRun = $localInstaller
                        }
                    } else {
                        Write-Host "      [ERROR] Local installer not found at $localInstaller." -ForegroundColor Red
                    }
                }
                "4" {
                    if (Test-Path $uncInstaller) {
                        Write-Host "      [Network Share] Copying installer from Network Share to Local Disk ($tempInstaller)..." -ForegroundColor Gray
                        $copySuccess = $false
                        try {
                            if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                                Start-BitsTransfer -Source $uncInstaller -Destination $tempInstaller -ErrorAction Stop
                                $copySuccess = $true
                            }
                        } catch { $copySuccess = $false }

                        if (-not $copySuccess) {
                            try {
                                Copy-Item -Path $uncInstaller -Destination $tempInstaller -Force -ErrorAction Stop
                                $copySuccess = $true
                            } catch { Write-Host "      [WARN] Standard copy failed: $_" -ForegroundColor Red }
                        }

                        if (Test-Path $tempInstaller) {
                            $targetInstallerToRun = $tempInstaller
                            Write-Host "      [OK] Copied to Local Disk successfully." -ForegroundColor Green
                        } else {
                            $targetInstallerToRun = $uncInstaller
                        }
                    } else {
                        Write-Host "      [ERROR] Network share installer not found at $uncInstaller." -ForegroundColor Red
                    }
                }
                default {
                    # Auto-Detect mode
                    if ($fdInstaller) {
                        Write-Host "      [Auto-Detect: USB] Copying installer from USB to Local Disk ($tempInstaller)..." -ForegroundColor Gray
                        Copy-Item -Path $fdInstaller -Destination $tempInstaller -Force -ErrorAction SilentlyContinue
                        if (Test-Path $tempInstaller) {
                            $targetInstallerToRun = $tempInstaller
                            Write-Host "      [OK] Copied to Local Disk. You can now safely EJECT your Flash Drive (USB)!" -ForegroundColor Green
                        } else {
                            $targetInstallerToRun = $fdInstaller
                        }
                    } elseif (Test-Path $localInstaller) {
                        Write-Host "      [Auto-Detect: Local] Copying installer to Local Temp ($tempInstaller)..." -ForegroundColor Gray
                        Copy-Item -Path $localInstaller -Destination $tempInstaller -Force -ErrorAction SilentlyContinue
                        if (Test-Path $tempInstaller) { $targetInstallerToRun = $tempInstaller } else { $targetInstallerToRun = $localInstaller }
                    } elseif (Test-Path $uncInstaller) {
                        Write-Host "      [Auto-Detect: Network Share] Copying installer to Local Disk ($tempInstaller)..." -ForegroundColor Gray
                        $copySuccess = $false
                        try {
                            if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                                Start-BitsTransfer -Source $uncInstaller -Destination $tempInstaller -ErrorAction Stop
                                $copySuccess = $true
                            }
                        } catch { $copySuccess = $false }

                        if (-not $copySuccess) {
                            try {
                                Copy-Item -Path $uncInstaller -Destination $tempInstaller -Force -ErrorAction Stop
                                $copySuccess = $true
                            } catch {}
                        }

                        if (Test-Path $tempInstaller) {
                            $targetInstallerToRun = $tempInstaller
                            Write-Host "      [OK] Copied to Local Disk successfully." -ForegroundColor Green
                        } else {
                            $targetInstallerToRun = $uncInstaller
                        }
                    }
                }
            }

            if ($targetInstallerToRun -and (Test-Path $targetInstallerToRun)) {
                Write-Host "      [Executing] Launching Kaspersky installer from Local Disk ($targetInstallerToRun)..." -ForegroundColor Yellow
                $proc = Start-Process -FilePath $targetInstallerToRun -Wait -PassThru
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                    Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                } else {
                    Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                }
                
                # Cleanup local temp installer after execution finishes
                if ($targetInstallerToRun -eq $tempInstaller) {
                    Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "      [ERROR] Unable to locate or prepare Kaspersky installer." -ForegroundColor Red
            }

            Write-Host "`n[OK] Kaspersky task completed." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "9" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "             SOFTWARE TELEMETRY & POP-UP BLOCKER MANAGER                 " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   [A] Apply All Blockers (AutoCAD + EaseUS Full Protection)" -ForegroundColor Green
                Write-Host ""
                Write-Host "   --- Select Application to Manage ---" -ForegroundColor Yellow
                Write-Host "   [1] Autodesk AutoCAD (All Versions)  (Genuine Service, Firewall & Hosts)"
                Write-Host "   [2] EaseUS Software Products         (Partition Master, Data Recovery, Todo Backup)"
                Write-Host "   [3] Unblock All Software & Reset     (Restore Default Hosts & Firewall Rules)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $blockerChoice = Read-Host "Select option (A / 1-3 / 0)"
                if ($blockerChoice -eq "0") {
                    break
                }
                switch ($blockerChoice.ToUpper()) {
                    "A" {
                        Write-Host "`nApplying Full Protection for AutoCAD and EaseUS Suite..." -ForegroundColor Yellow
                        
                        # --- 1. AutoCAD Protection ---
                        Write-Host "`n[1/2] Applying Autodesk AutoCAD Protection..." -ForegroundColor Cyan
                        Stop-Service -Name "Autodesk Genuine Service", "AdskLicensingService", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                        Set-Service -Name "Autodesk Genuine Service" -StartupType Disabled -ErrorAction SilentlyContinue
                        Set-Service -Name "AdAppMgr-Service" -StartupType Disabled -ErrorAction SilentlyContinue
                        Stop-Process -Name "GenuineService", "AdskLicensingAgent", "AdskIdentityManager", "AutodeskDesktopApp", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                        $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
                        if (-not (Test-Path $ifeoPath)) { New-Item -Path $ifeoPath -Force | Out-Null }
                        Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "systray.exe" -Force -ErrorAction SilentlyContinue

                        $acadPaths = @(Get-ChildItem -Path "C:\Program Files\Autodesk", "C:\Program Files (x86)\Autodesk" -Filter "acad.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                        $staticBinaries = @(
                            "C:\Program Files\Autodesk\Autodesk Genuine Service\GenuineService.exe",
                            "C:\Program Files\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingAgent\AdskLicensingAgent.exe",
                            "C:\Program Files (x86)\Autodesk\Autodesk Desktop App\AutodeskDesktopApp.exe",
                            "C:\Program Files (x86)\Common Files\Autodesk Shared\AppManager\R1\AdAppMgr-Service.exe",
                            "C:\Program Files\Common Files\Autodesk Shared\AdLM\R14\LTU.exe",
                            "C:\Program Files\Common Files\Autodesk Shared\AdLM\R15\LTU.exe"
                        )
                        foreach ($bin in ($acadPaths + $staticBinaries | Select-Object -Unique)) {
                            if (Test-Path $bin) {
                                $bName = (Get-Item $bin).BaseName
                                $pDir = (Get-Item $bin).Directory.Name
                                $ruleName = "Block Autodesk ($pDir - $bName)"
                                netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                            }
                        }

                        # --- 2. EaseUS Protection ---
                        Write-Host "`n[2/2] Applying EaseUS Suite Protection..." -ForegroundColor Cyan
                        Get-Service -Name "*EaseUS*", "*EuWatch*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
                        Stop-Process -Name "Main", "DRW", "DRWUI", "EaseUS*", "EuUpgrade*", "TBMain", "TBEnterprise*" -Force -ErrorAction SilentlyContinue

                        $easeusFolders = @("C:\Program Files\EaseUS", "C:\Program Files (x86)\EaseUS")
                        $easeusBins = @()
                        foreach ($ef in $easeusFolders) {
                            if (Test-Path $ef) {
                                $easeusBins += (Get-ChildItem -Path $ef -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                            }
                        }
                        foreach ($bin in ($easeusBins | Select-Object -Unique)) {
                            if (Test-Path $bin) {
                                $bName = (Get-Item $bin).BaseName
                                $pDir = (Get-Item $bin).Directory.Name
                                $ruleName = "Block EaseUS ($pDir - $bName)"
                                netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                            }
                        }

                        # --- 3. Combined Hosts File ---
                        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                        Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                        $combinedDomains = @(
                            "127.0.0.1 genuine-software2.autodesk.com", "127.0.0.1 genuine-software.autodesk.com", "127.0.0.1 ipm-provider.autodesk.com", "127.0.0.1 api.autodesk.com", "127.0.0.1 developer.api.autodesk.com", "127.0.0.1 curson.autodesk.com", "127.0.0.1 registeronce.autodesk.com", "127.0.0.1 asset-direct.autodesk.com", "127.0.0.1 analytics.autodesk.com", "127.0.0.1 clm.autodesk.com", "127.0.0.1 lic.autodesk.com", "127.0.0.1 access.clm.autodesk.com", "127.0.0.1 genuine-software1.autodesk.com",
                            "127.0.0.1 track.easeus.com", "127.0.0.1 tracking.easeus.com", "127.0.0.1 api.easeus.com", "127.0.0.1 apiv2.easeus.com", "127.0.0.1 activation.easeus.com", "127.0.0.1 stats.easeus.com", "127.0.0.1 update.easeus.com", "127.0.0.1 upgrade.easeus.com", "127.0.0.1 store.easeus.com", "127.0.0.1 cdn.easeus.com"
                        )
                        $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
                        foreach ($entry in $combinedDomains) {
                            if ($existingHosts -notcontains $entry) { Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue }
                        }
                        Clear-DnsClientCache -ErrorAction SilentlyContinue

                        Write-Host "`n[OK] Full Protection for AutoCAD and EaseUS applied successfully!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "1" {
                        # AutoCAD Submenu
                        while ($true) {
                            Clear-Host
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host "               AUTODESK AUTOCAD TELEMETRY BLOCKER MANAGER                " -ForegroundColor Cyan
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host ""
                            Write-Host "   [1] Apply Full AutoCAD Protection      (Services, Firewall & Hosts)"
                            Write-Host "   [2] Disable Autodesk Genuine Service   (Stop Service, Process & IFEO Lock)"
                            Write-Host "   [3] Block AutoCAD Firewall (All)       (Auto-Scan & Block Inbound/Outbound acad.exe)"
                            Write-Host "   [4] Block AutoCAD Domains in Hosts     (Redirect Autodesk Domains to 127.0.0.1)"
                            Write-Host "   [5] Unblock / Reset AutoCAD Rules      (Remove Rules & Restore Hosts File)"
                            Write-Host ""
                            Write-Host "   [0] Back to Blocker Menu" -ForegroundColor Red
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host ""

                            $subCad = Read-Host "Select option (0-5)"
                            if ($subCad -eq "0") { break }

                            switch ($subCad) {
                                "1" {
                                    Write-Host "`nApplying Full AutoCAD Telemetry & License Protection..." -ForegroundColor Yellow
                                    Stop-Service -Name "Autodesk Genuine Service", "AdskLicensingService", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                                    Set-Service -Name "Autodesk Genuine Service" -StartupType Disabled -ErrorAction SilentlyContinue
                                    Set-Service -Name "AdAppMgr-Service" -StartupType Disabled -ErrorAction SilentlyContinue
                                    Stop-Process -Name "GenuineService", "AdskLicensingAgent", "AdskIdentityManager", "AutodeskDesktopApp", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                                    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
                                    if (-not (Test-Path $ifeoPath)) { New-Item -Path $ifeoPath -Force | Out-Null }
                                    Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "systray.exe" -Force -ErrorAction SilentlyContinue

                                    $acadPaths = @(Get-ChildItem -Path "C:\Program Files\Autodesk", "C:\Program Files (x86)\Autodesk" -Filter "acad.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                                    $staticBinaries = @(
                                        "C:\Program Files\Autodesk\Autodesk Genuine Service\GenuineService.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingAgent\AdskLicensingAgent.exe",
                                        "C:\Program Files (x86)\Autodesk\Autodesk Desktop App\AutodeskDesktopApp.exe",
                                        "C:\Program Files (x86)\Common Files\Autodesk Shared\AppManager\R1\AdAppMgr-Service.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdLM\R14\LTU.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdLM\R15\LTU.exe"
                                    )
                                    foreach ($bin in ($acadPaths + $staticBinaries | Select-Object -Unique)) {
                                        if (Test-Path $bin) {
                                            $bName = (Get-Item $bin).BaseName
                                            $pDir = (Get-Item $bin).Directory.Name
                                            $ruleName = "Block Autodesk ($pDir - $bName)"
                                            netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                            netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                                        }
                                    }

                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                                    Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                                    $domainsToBlock = @("127.0.0.1 genuine-software2.autodesk.com", "127.0.0.1 genuine-software.autodesk.com", "127.0.0.1 ipm-provider.autodesk.com", "127.0.0.1 api.autodesk.com", "127.0.0.1 developer.api.autodesk.com", "127.0.0.1 curson.autodesk.com", "127.0.0.1 registeronce.autodesk.com", "127.0.0.1 asset-direct.autodesk.com", "127.0.0.1 analytics.autodesk.com", "127.0.0.1 clm.autodesk.com", "127.0.0.1 lic.autodesk.com", "127.0.0.1 access.clm.autodesk.com", "127.0.0.1 genuine-software1.autodesk.com")
                                    $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
                                    foreach ($entry in $domainsToBlock) {
                                        if ($existingHosts -notcontains $entry) { Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue }
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "`n[OK] AutoCAD Protection applied successfully!" -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "2" {
                                    Write-Host "`nDisabling Autodesk Genuine & Licensing Services..." -ForegroundColor Yellow
                                    Stop-Service -Name "Autodesk Genuine Service", "AdskLicensingService", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                                    Set-Service -Name "Autodesk Genuine Service" -StartupType Disabled -ErrorAction SilentlyContinue
                                    Set-Service -Name "AdAppMgr-Service" -StartupType Disabled -ErrorAction SilentlyContinue
                                    Stop-Process -Name "GenuineService", "AdskLicensingAgent", "AdskIdentityManager", "AutodeskDesktopApp", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
                                    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
                                    if (-not (Test-Path $ifeoPath)) { New-Item -Path $ifeoPath -Force | Out-Null }
                                    Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "systray.exe" -Force -ErrorAction SilentlyContinue
                                    Write-Host "[OK] Genuine Service stopped & IFEO locked." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "3" {
                                    Write-Host "`nScanning and blocking Firewall for all installed AutoCAD versions..." -ForegroundColor Yellow
                                    $acadPaths = @(Get-ChildItem -Path "C:\Program Files\Autodesk", "C:\Program Files (x86)\Autodesk" -Filter "acad.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                                    $staticBinaries = @(
                                        "C:\Program Files\Autodesk\Autodesk Genuine Service\GenuineService.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingAgent\AdskLicensingAgent.exe",
                                        "C:\Program Files (x86)\Autodesk\Autodesk Desktop App\AutodeskDesktopApp.exe",
                                        "C:\Program Files (x86)\Common Files\Autodesk Shared\AppManager\R1\AdAppMgr-Service.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdLM\R14\LTU.exe",
                                        "C:\Program Files\Common Files\Autodesk Shared\AdLM\R15\LTU.exe"
                                    )
                                    $blockedCount = 0
                                    foreach ($bin in ($acadPaths + $staticBinaries | Select-Object -Unique)) {
                                        if (Test-Path $bin) {
                                            $bName = (Get-Item $bin).BaseName
                                            $pDir = (Get-Item $bin).Directory.Name
                                            $ruleName = "Block Autodesk ($pDir - $bName)"
                                            netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                            netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                                            $blockedCount++
                                        }
                                    }
                                    Write-Host "[OK] $blockedCount AutoCAD executables blocked in Firewall." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "4" {
                                    Write-Host "`nBlocking AutoCAD domains in Hosts file..." -ForegroundColor Yellow
                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                                    Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                                    $domainsToBlock = @("127.0.0.1 genuine-software2.autodesk.com", "127.0.0.1 genuine-software.autodesk.com", "127.0.0.1 ipm-provider.autodesk.com", "127.0.0.1 api.autodesk.com", "127.0.0.1 developer.api.autodesk.com", "127.0.0.1 curson.autodesk.com", "127.0.0.1 registeronce.autodesk.com", "127.0.0.1 asset-direct.autodesk.com", "127.0.0.1 analytics.autodesk.com", "127.0.0.1 clm.autodesk.com", "127.0.0.1 lic.autodesk.com", "127.0.0.1 access.clm.autodesk.com", "127.0.0.1 genuine-software1.autodesk.com")
                                    $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
                                    foreach ($entry in $domainsToBlock) {
                                        if ($existingHosts -notcontains $entry) { Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue }
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "[OK] AutoCAD domains redirected to 127.0.0.1." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "5" {
                                    Write-Host "`nResetting AutoCAD firewall rules and hosts..." -ForegroundColor Yellow
                                    netsh advfirewall firewall delete rule name="all" program="acad.exe" >$null 2>&1
                                    netsh advfirewall firewall delete rule name="Block Autodesk*" >$null 2>&1
                                    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
                                    if (Test-Path $ifeoPath) { Remove-Item -Path $ifeoPath -Recurse -Force -ErrorAction SilentlyContinue }
                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    if (Test-Path $hostsPath) {
                                        $lines = Get-Content $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -notlike "*autodesk.com*" }
                                        $lines | Set-Content $hostsPath -Force -ErrorAction SilentlyContinue
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "[OK] AutoCAD rules reset successfully." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                            }
                        }
                    }
                    "2" {
                        # EaseUS Submenu
                        while ($true) {
                            Clear-Host
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host "               EASEUS PRODUCTS TELEMETRY BLOCKER MANAGER                 " -ForegroundColor Cyan
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host ""
                            Write-Host "   [1] Apply Full EaseUS Protection       (Firewall Block, Hosts Redirect & Services)"
                            Write-Host "   [2] Block EaseUS Firewall Binaries     (Partition Master, Data Recovery, Todo Backup)"
                            Write-Host "   [3] Block EaseUS Domains in Hosts      (Redirect EaseUS Tracking & Update Servers)"
                            Write-Host "   [4] Unblock / Reset EaseUS Blockers    (Restore Firewall & Hosts File)"
                            Write-Host ""
                            Write-Host "   [0] Back to Blocker Menu" -ForegroundColor Red
                            Write-Host "=========================================================================" -ForegroundColor Cyan
                            Write-Host ""

                            $subEase = Read-Host "Select option (0-4)"
                            if ($subEase -eq "0") { break }

                            switch ($subEase) {
                                "1" {
                                    Write-Host "`nApplying Full EaseUS Telemetry & Pop-up Protection..." -ForegroundColor Yellow
                                    Get-Service -Name "*EaseUS*", "*EuWatch*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
                                    Stop-Process -Name "Main", "DRW", "DRWUI", "EaseUS*", "EuUpgrade*", "TBMain", "TBEnterprise*" -Force -ErrorAction SilentlyContinue

                                    $easeusFolders = @("C:\Program Files\EaseUS", "C:\Program Files (x86)\EaseUS")
                                    $easeusBins = @()
                                    foreach ($ef in $easeusFolders) {
                                        if (Test-Path $ef) {
                                            $easeusBins += (Get-ChildItem -Path $ef -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                                        }
                                    }
                                    $blockedCount = 0
                                    foreach ($bin in ($easeusBins | Select-Object -Unique)) {
                                        if (Test-Path $bin) {
                                            $bName = (Get-Item $bin).BaseName
                                            $pDir = (Get-Item $bin).Directory.Name
                                            $ruleName = "Block EaseUS ($pDir - $bName)"
                                            netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                            netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                                            $blockedCount++
                                        }
                                    }

                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                                    Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                                    $easeDomains = @("127.0.0.1 track.easeus.com", "127.0.0.1 tracking.easeus.com", "127.0.0.1 api.easeus.com", "127.0.0.1 apiv2.easeus.com", "127.0.0.1 activation.easeus.com", "127.0.0.1 stats.easeus.com", "127.0.0.1 update.easeus.com", "127.0.0.1 upgrade.easeus.com", "127.0.0.1 store.easeus.com", "127.0.0.1 cdn.easeus.com")
                                    $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
                                    foreach ($entry in $easeDomains) {
                                        if ($existingHosts -notcontains $entry) { Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue }
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "`n[OK] Full EaseUS Protection applied ($blockedCount binaries blocked)!" -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "2" {
                                    Write-Host "`nScanning and blocking EaseUS application binaries in Firewall..." -ForegroundColor Yellow
                                    $easeusFolders = @("C:\Program Files\EaseUS", "C:\Program Files (x86)\EaseUS")
                                    $easeusBins = @()
                                    foreach ($ef in $easeusFolders) {
                                        if (Test-Path $ef) {
                                            $easeusBins += (Get-ChildItem -Path $ef -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                                        }
                                    }
                                    $blockedCount = 0
                                    foreach ($bin in ($easeusBins | Select-Object -Unique)) {
                                        if (Test-Path $bin) {
                                            $bName = (Get-Item $bin).BaseName
                                            $pDir = (Get-Item $bin).Directory.Name
                                            $ruleName = "Block EaseUS ($pDir - $bName)"
                                            netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                                            netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                                            netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                                            $blockedCount++
                                        }
                                    }
                                    Write-Host "[OK] $blockedCount EaseUS executables blocked in Firewall." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "3" {
                                    Write-Host "`nBlocking EaseUS telemetry & tracking domains in Hosts file..." -ForegroundColor Yellow
                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
                                    Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                                    $easeDomains = @("127.0.0.1 track.easeus.com", "127.0.0.1 tracking.easeus.com", "127.0.0.1 api.easeus.com", "127.0.0.1 apiv2.easeus.com", "127.0.0.1 activation.easeus.com", "127.0.0.1 stats.easeus.com", "127.0.0.1 update.easeus.com", "127.0.0.1 upgrade.easeus.com", "127.0.0.1 store.easeus.com", "127.0.0.1 cdn.easeus.com")
                                    $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
                                    foreach ($entry in $easeDomains) {
                                        if ($existingHosts -notcontains $entry) { Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue }
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "[OK] EaseUS domains redirected to 127.0.0.1." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                                "4" {
                                    Write-Host "`nResetting EaseUS firewall rules and hosts file..." -ForegroundColor Yellow
                                    netsh advfirewall firewall delete rule name="Block EaseUS*" >$null 2>&1
                                    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                                    if (Test-Path $hostsPath) {
                                        $lines = Get-Content $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -notlike "*easeus.com*" }
                                        $lines | Set-Content $hostsPath -Force -ErrorAction SilentlyContinue
                                    }
                                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                                    Write-Host "[OK] EaseUS blocker rules have been reset." -ForegroundColor Green
                                    Start-Sleep -Seconds 2
                                }
                            }
                        }
                    }
                    "3" {
                        Write-Host "`nUnblocking all software rules and restoring hosts file..." -ForegroundColor Yellow
                        netsh advfirewall firewall delete rule name="all" program="acad.exe" >$null 2>&1
                        netsh advfirewall firewall delete rule name="Block Autodesk*" >$null 2>&1
                        netsh advfirewall firewall delete rule name="Block EaseUS*" >$null 2>&1

                        $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
                        if (Test-Path $ifeoPath) { Remove-Item -Path $ifeoPath -Recurse -Force -ErrorAction SilentlyContinue }

                        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                        if (Test-Path $hostsPath) {
                            $lines = Get-Content $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -notlike "*autodesk.com*" -and $_ -notlike "*easeus.com*" }
                            $lines | Set-Content $hostsPath -Force -ErrorAction SilentlyContinue
                        }
                        Clear-DnsClientCache -ErrorAction SilentlyContinue
                        Write-Host "[OK] All software blocker rules reset to factory defaults." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "0" { break }
                }
            }
        }
        "10" {
            while ($true) {
                Clear-Host
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "                  SMB SHARE & BROADCAST STEALTH MANAGER                  " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   --- Active Custom SMB Shares ---" -ForegroundColor Yellow
                $shares = Get-SmbShare | Where-Object { -not $_.Special }
                if ($shares) {
                    $shares | Format-Table Name, Path, Description -AutoSize | Out-String | Write-Host -ForegroundColor White
                } else {
                    Write-Host "   (No active custom SMB shares found)`n" -ForegroundColor Gray
                }

                $fdStatus = (Get-Service -Name "FDResPub" -ErrorAction SilentlyContinue).Status
                $fdColor = if ($fdStatus -eq "Running") { "Green" } else { "Red" }
                Write-Host "   Network Discovery / Broadcast (FDResPub): $fdStatus" -ForegroundColor $fdColor
                Write-Host ""
                Write-Host "   [1] Convert Public Share to Hidden Share ($)  (Invisible in Network View)"
                Write-Host "   [2] Convert Hidden Share ($) to Public Share  (Visible in Network View)"
                Write-Host "   [3] Create New Hidden Share ($) from Folder   (Anonymous Full Access)"
                Write-Host "   [4] Toggle PC Network Broadcast / Discovery   (Hide/Show PC in Network Tab)"
                Write-Host "   [5] Flush NetBIOS / SMB Sessions on this PC   (Clear Stale Network Cache)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $smbChoice = Read-Host "Select SMB option (0-5)"
                if ($smbChoice -eq "0") {
                    break
                }
                switch ($smbChoice) {
                    "1" {
                        $sName = Read-Host "`nEnter name of share to hide (e.g. Sharing)"
                        $targetShare = Get-SmbShare -Name $sName -ErrorAction SilentlyContinue
                        if ($targetShare) {
                            $sPath = $targetShare.Path
                            Remove-SmbShare -Name $sName -Force
                            New-SmbShare -Name "$sName`$" -Path $sPath -FullAccess "Everyone" -Description "Hidden Share" | Out-Null
                            Write-Host "`n[OK] Share converted to hidden: \\$env:COMPUTERNAME\$sName`$" -ForegroundColor Green
                        } else {
                            Write-Host "`n[ERROR] Share '$sName' not found." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        $sName = Read-Host "`nEnter name of hidden share to unhide (e.g. Sharing$)"
                        $targetShare = Get-SmbShare -Name $sName -ErrorAction SilentlyContinue
                        if ($targetShare) {
                            $sPath = $targetShare.Path
                            $cleanName = $sName.TrimEnd('$')
                            Remove-SmbShare -Name $sName -Force
                            New-SmbShare -Name $cleanName -Path $sPath -FullAccess "Everyone" -Description "Public Share" | Out-Null
                            Write-Host "`n[OK] Share converted to public: \\$env:COMPUTERNAME\$cleanName" -ForegroundColor Green
                        } else {
                            Write-Host "`n[ERROR] Share '$sName' not found." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        $fPath = Read-Host "`nEnter full folder path to share (e.g. D:\Data)"
                        if (Test-Path $fPath) {
                            $defaultName = (Get-Item $fPath).Name
                            $sName = Read-Host "Enter share name (default: $defaultName)"
                            if ([string]::IsNullOrWhiteSpace($sName)) { $sName = $defaultName }
                            if (-not $sName.EndsWith('$')) { $sName = "$sName`$" }
                            
                            # Set NTFS Permission for Everyone
                            icacls "$fPath" /grant "Everyone:(OI)(CI)F" /T /C /Q | Out-Null
                            icacls "$fPath" /grant "Authenticated Users:(OI)(CI)F" /T /C /Q | Out-Null
                            
                            New-SmbShare -Name $sName -Path $fPath -FullAccess "Everyone" -Description "Hidden Share" | Out-Null
                            Write-Host "`n[OK] Hidden share created: \\$env:COMPUTERNAME\$sName" -ForegroundColor Green
                        } else {
                            Write-Host "`n[ERROR] Folder '$fPath' does not exist." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "4" {
                        $svc = Get-Service -Name "FDResPub" -ErrorAction SilentlyContinue
                        if ($svc.Status -eq "Running") {
                            Write-Host "`nDisabling PC Network Discovery / Broadcast..." -ForegroundColor Yellow
                            Stop-Service -Name "FDResPub" -Force -ErrorAction SilentlyContinue
                            Set-Service -Name "FDResPub" -StartupType Disabled
                            Write-Host "[OK] PC is now HIDDEN from Network View on other computers." -ForegroundColor Green
                        } else {
                            Write-Host "`nEnabling PC Network Discovery / Broadcast..." -ForegroundColor Yellow
                            Set-Service -Name "FDResPub" -StartupType Automatic
                            Start-Service -Name "FDResPub" -ErrorAction SilentlyContinue
                            Write-Host "[OK] PC is now VISIBLE in Network View on other computers." -ForegroundColor Green
                        }
                        Start-Sleep -Seconds 2
                    }
                    "5" {
                        Write-Host "`nFlushing DNS, NetBIOS & SMB Sessions..." -ForegroundColor Yellow
                        ipconfig /flushdns | Out-Null
                        nbtstat -R | Out-Null
                        nbtstat -RR | Out-Null
                        net use * /delete /y >$null 2>&1
                        Write-Host "[OK] Network cache & SMB sessions flushed successfully." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "0" { break }
                }
            }
        }
        "11" {
            Clear-Host
            Write-Host "=========================================================================" -ForegroundColor Cyan
            Write-Host "             FAST MULTITHREADED NETWORK SCANNER (LAN)                    " -ForegroundColor Cyan
            Write-Host "=========================================================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Detect active IPv4 subnets
            $ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
            $subnets = @()
            foreach ($ip in $ips) {
                $parts = $ip.IPAddress.Split('.')
                if ($parts.Count -eq 4) {
                    $sub = "$($parts[0]).$($parts[1]).$($parts[2])"
                    if ($subnets -notcontains $sub) {
                        $subnets += $sub
                    }
                }
            }

            Write-Host "Active Subnets Detected:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $subnets.Count; $i++) {
                Write-Host "  [$($i + 1)] $($subnets[$i]).0/24 ($($ips[$i].InterfaceAlias))"
            }
            Write-Host "  [C] Custom Subnet Input (e.g. 192.168.10 or 172.168.39)"
            Write-Host "  [A] Scan All Detected Subnets"
            Write-Host "  [0] Back to Main Menu" -ForegroundColor Red
            Write-Host ""

            $scanChoice = Read-Host "Select option (1-$($subnets.Count) / C / A / 0)"
            $chosenSubnets = @()

            if ($scanChoice -eq '0') {
                continue
            } elseif ($scanChoice -match '^\d+$' -and [int]$scanChoice -ge 1 -and [int]$scanChoice -le $subnets.Count) {
                $chosenSubnets += $subnets[[int]$scanChoice - 1]
            } elseif ($scanChoice.ToUpper() -eq 'C') {
                $custom = Read-Host "`nEnter first 3 octets of subnet (e.g. 192.168.10)"
                if ($custom -match '^\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                    $chosenSubnets += $custom
                } else {
                    Write-Host "[ERROR] Invalid subnet format!" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            } elseif ($scanChoice.ToUpper() -eq 'A') {
                $chosenSubnets = $subnets
            }

            if ($chosenSubnets.Count -gt 0) {
                $timeout = 400
                $results = @()

                foreach ($subnet in $chosenSubnets) {
                    Write-Host "`nScanning subnet: $subnet.0/24..." -ForegroundColor Yellow
                    $tasks = @()
                    $pings = @()
                    
                    1..254 | ForEach-Object {
                        $ip = "$subnet.$_"
                        $p = New-Object System.Net.NetworkInformation.Ping
                        $pings += $p
                        try {
                            $tasks += $p.SendPingAsync($ip, $timeout)
                        } catch {}
                    }

                    try {
                        [System.Threading.Tasks.Task]::WaitAll($tasks)
                    } catch {}

                    for ($i = 0; $i -lt $tasks.Count; $i++) {
                        try {
                            if ($tasks[$i].IsCompleted -and $null -ne $tasks[$i].Result -and $tasks[$i].Result.Status -eq "Success") {
                                $ip = $tasks[$i].Result.Address.IPAddressToString
                                
                                $hostname = "Unknown"
                                try {
                                    $hostEntry = [System.Net.Dns]::GetHostEntry($ip)
                                    $hostname = $hostEntry.HostName
                                } catch {}
                                
                                $results += [PSCustomObject]@{
                                    Subnet    = "$subnet.0/24"
                                    IPAddress = $ip
                                    Hostname  = $hostname
                                }
                                Write-Host "  [*] Online: $ip ($hostname)" -ForegroundColor Green
                            }
                        } catch {}
                    }
                }

                Write-Host "`n=========================================================================" -ForegroundColor Cyan
                Write-Host "                        SCAN RESULTS SUMMARY                             " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                if ($results.Count -gt 0) {
                    $results | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
                    Write-Host "Total Active Devices Found: $($results.Count)" -ForegroundColor Green
                } else {
                    Write-Host "No active devices found in the selected range." -ForegroundColor Yellow
                }
                Write-Host "=========================================================================" -ForegroundColor Cyan

                Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
                Read-Host | Out-Null
            }
        }
        "12" {
            while ($true) {
                Clear-Host
                $winEdition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
                $rdpStatus = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
                $statusText = if ($rdpStatus -eq 0) { "ENABLED (Connections Allowed)" } else { "DISABLED (Connections Denied)" }
                $statusColor = if ($rdpStatus -eq 0) { "Green" } else { "Red" }

                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host "                  REMOTE DESKTOP (RDP) MANAGER                           " -ForegroundColor Cyan
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   Windows Edition Detected : $winEdition" -ForegroundColor Yellow
                Write-Host "   Native RDP Server Status : $statusText" -ForegroundColor $statusColor
                Write-Host ""
                Write-Host "   [1] Enable Native RDP & Open Firewall (Pro / Enterprise / Education)"
                Write-Host "   [2] Disable Native RDP & Block Port   (Close Port 3389 & Deny Connections)"
                Write-Host "   [3] Enable RDP on Windows Home        (Auto-Install/Update RDP Wrapper + ini)"
                Write-Host "   [4] Update RDPWrap.ini to Latest      (Download Community Fix for Windows Updates)"
                Write-Host "   [5] Check RDP Status / Test Listener  (Verify Port 3389 and Services)"
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $rdpChoice = Read-Host "Select option (0-5)"
                if ($rdpChoice -eq "0") {
                    break
                }
                switch ($rdpChoice) {
                    "1" {
                        Write-Host "`nEnabling Native Remote Desktop and Configuring Firewall..." -ForegroundColor Yellow
                        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
                        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Type DWord -Force
                        Set-Service -Name "TermService" -StartupType Automatic -ErrorAction SilentlyContinue
                        Start-Service -Name "TermService" -ErrorAction SilentlyContinue

                        # Open Firewall Rules
                        netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >$null 2>&1
                        netsh advfirewall firewall add rule name="Allow RDP Port 3389" dir=in action=allow protocol=TCP localport=3389 >$null 2>&1
                        netsh advfirewall firewall add rule name="Allow RDP UDP 3389" dir=in action=allow protocol=UDP localport=3389 >$null 2>&1
                        
                        Write-Host "[OK] Native Remote Desktop enabled and port 3389 opened." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        Write-Host "`nDisabling Remote Desktop and Closing Firewall..." -ForegroundColor Yellow
                        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1 -Type DWord -Force
                        netsh advfirewall firewall set rule group="remote desktop" new enable=No >$null 2>&1
                        netsh advfirewall firewall delete rule name="Allow RDP Port 3389" >$null 2>&1
                        netsh advfirewall firewall delete rule name="Allow RDP UDP 3389" >$null 2>&1
                        
                        Write-Host "[OK] Remote Desktop disabled." -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        Write-Host "`nSetting up RDP Wrapper for Windows Home Edition..." -ForegroundColor Yellow
                        $rdpDir = "$env:ProgramFiles\RDP Wrapper"
                        if (-not (Test-Path $rdpDir)) { New-Item -Path $rdpDir -ItemType Directory -Force | Out-Null }

                        # 1. Enable Registry and Services
                        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
                        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Type DWord -Force
                        Set-Service -Name "TermService" -StartupType Automatic -ErrorAction SilentlyContinue
                        
                        # 2. Add Windows Defender Exclusion for RDP Wrapper directory
                        Write-Host "      [1/3] Adding Antivirus / Defender exclusions..." -ForegroundColor Gray
                        Add-MpPreference -ExclusionPath $rdpDir -ErrorAction SilentlyContinue
                        Add-MpPreference -ExclusionProcess "rdpwrap.dll" -ErrorAction SilentlyContinue

                        # 3. Download RDP Wrapper binary if missing
                        $dllPath = "$rdpDir\rdpwrap.dll"
                        if (-not (Test-Path $dllPath)) {
                            Write-Host "      [2/3] Downloading rdpwrap.dll from repository..." -ForegroundColor Gray
                            try {
                                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                                Invoke-WebRequest -Uri "https://github.com/stascorp/rdpwrap/raw/master/res/rdpwrap.dll" -OutFile $dllPath -UseBasicParsing -ErrorAction Stop
                            } catch {
                                Write-Host "      [WARN] Could not auto-download rdpwrap.dll: $_" -ForegroundColor Red
                            }
                        }

                        # 4. Download latest community rdpwrap.ini
                        Write-Host "      [3/3] Fetching latest community rdpwrap.ini definitions..." -ForegroundColor Gray
                        $iniUrls = @(
                            "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini",
                            "https://raw.githubusercontent.com/affinityvr/rdpwrap.ini/master/rdpwrap.ini",
                            "https://raw.githubusercontent.com/stascorp/rdpwrap/master/res/rdpwrap.ini"
                        )
                        $iniSuccess = $false
                        foreach ($url in $iniUrls) {
                            try {
                                Invoke-WebRequest -Uri $url -OutFile "$rdpDir\rdpwrap.ini" -UseBasicParsing -ErrorAction Stop
                                $iniSuccess = $true
                                break
                            } catch {}
                        }

                        # 5. Register Hook & Restart Service
                        if (Test-Path $dllPath) {
                            Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters" -Name "ServiceDll" -Value $dllPath -Type ExpandString -Force -ErrorAction SilentlyContinue
                            Start-Service -Name "TermService" -ErrorAction SilentlyContinue
                        }

                        # Open Firewall
                        netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >$null 2>&1
                        netsh advfirewall firewall add rule name="Allow RDP Port 3389" dir=in action=allow protocol=TCP localport=3389 >$null 2>&1

                        Write-Host "`n[OK] RDP Wrapper setup completed for Windows Home!" -ForegroundColor Green
                        Start-Sleep -Seconds 2
                    }
                    "4" {
                        Write-Host "`nUpdating rdpwrap.ini to latest community version..." -ForegroundColor Yellow
                        $rdpDir = "$env:ProgramFiles\RDP Wrapper"
                        if (-not (Test-Path $rdpDir)) { New-Item -Path $rdpDir -ItemType Directory -Force | Out-Null }
                        
                        Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                        
                        $iniUrls = @(
                            "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini",
                            "https://raw.githubusercontent.com/affinityvr/rdpwrap.ini/master/rdpwrap.ini"
                        )
                        $updated = $false
                        foreach ($url in $iniUrls) {
                            try {
                                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                                Invoke-WebRequest -Uri $url -OutFile "$rdpDir\rdpwrap.ini" -UseBasicParsing -ErrorAction Stop
                                $updated = $true
                                Write-Host "   [OK] Downloaded latest rdpwrap.ini definitions." -ForegroundColor Green
                                break
                            } catch {}
                        }

                        Start-Service -Name "TermService" -ErrorAction SilentlyContinue
                        if ($updated) {
                            Write-Host "[OK] rdpwrap.ini updated and TermService restarted." -ForegroundColor Green
                        } else {
                            Write-Host "[ERROR] Failed to fetch rdpwrap.ini from community mirrors." -ForegroundColor Red
                        }
                        Start-Sleep -Seconds 2
                    }
                    "5" {
                        Write-Host "`nChecking Remote Desktop Listener Status..." -ForegroundColor Yellow
                        $portCheck = Test-NetConnection -ComputerName "127.0.0.1" -Port 3389 -ErrorAction SilentlyContinue
                        $termSvc = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
                        
                        Write-Host "   TermService Status : $($termSvc.Status)" -ForegroundColor Cyan
                        Write-Host "   Port 3389 Listening: $($portCheck.TcpTestSucceeded)" -ForegroundColor (if ($portCheck.TcpTestSucceeded) { "Green" } else { "Red" })
                        
                        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
                        Write-Host "`nConnect from other PC using: mstsc /v:$ip" -ForegroundColor Yellow
                        
                        Write-Host "`nPress Enter to return..." -ForegroundColor Gray
                        Read-Host | Out-Null
                    }
                    "0" { break }
                }
            }
        }
        "0" { 
            exit 
        }
        default {
            Write-Host "`n[ERROR] Invalid option." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
