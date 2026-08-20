$ErrorActionPreference = 'Continue'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[INFO] Requesting Administrator Privileges..." -ForegroundColor Yellow
    $url = 'https://raw.githubusercontent.com/Bersa96/-it-toolkit/main/Install.ps1'
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -Command `"Invoke-RestMethod '$url' | Invoke-Expression`"" -Verb RunAs
    exit
}

while ($true) {
    Clear-Host
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "                    IT SUPPORT TOOLKIT - MENU UTAMA                      " -ForegroundColor Cyan
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1] Pasang Aplikasi Standar       (Chrome, Acrobat, WhatsApp, 7-Zip, AnyDesk, Zoom)"
    Write-Host "   [2] Optimasi & Tampilan Windows    (Mode Gelap, Tampilan Klasik, Privasi)"
    Write-Host "   [3] Perbaiki Sistem Rusak         (SFC Scannow & DISM RestoreHealth)"
    Write-Host "   [4] Perbaiki Print Spooler         (Bersihkan & Restart Antrean Cetak Macet)"
    Write-Host "   [5] Reset Jaringan & Optimasi WiFi (Flush DNS, Tuning TCP, Anti Lag/Drop)"
    Write-Host "   [6] Pengaturan Windows Update      (Jeda Update 9999 Hari / Lanjutkan)"
    Write-Host "   [7] Konfigurasi Lansweeper Agent   (Ubah Hostname, Buka Firewall & Pasang LsAgent)"
    Write-Host "   [8] Pasang Kaspersky Antivirus     (Bersihkan AV Lama & Aman Cabut Flashdisk)"
    Write-Host "   [9] Blokir Pop-up AutoCAD (Semua)  (Blokir Genuine Service & Lisensi Semua Versi)"
    Write-Host "   [10] Pengaturan Sharing Folder SMB  (Sembunyikan Share $, Matikan Broadcast PC)"
    Write-Host "   [11] Pindai Jaringan Lokal (LAN)    (Scan Cepat IP & Nama Komputer Aktif)"
    Write-Host ""
    Write-Host "   [0] Keluar" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Pilih menu (0-11)"

    switch ($choice) {
        "1" {
            Write-Host "`nInstalling Standard Apps..." -ForegroundColor Yellow
            
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

            $apps = @(
                @{ id = "WhatsApp.WhatsApp";               url = "https://desktop.whatsapp.com/releases/WinX64/WhatsAppSetup.exe"; out = "$env:TEMP\WA.exe"; args = "/silent" },
                @{ id = "Google.Chrome";                  url = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"; out = "$env:TEMP\Chrome.exe"; args = "/silent /install" },
                @{ id = "Adobe.Acrobat.Reader.64-bit";    url = "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2400120604/AcroRdrDC2400120604_en_US.exe"; out = "$env:TEMP\Acrobat.exe"; args = "/sAll /rs" },
                @{ id = "geekwright.PDF24";               url = "https://download.pdf24.org/pdf24-creator-11.15.2-x64.exe"; out = "$env:TEMP\PDF24.exe"; args = "/VERYSILENT /NORESTART" },
                @{ id = "7zip.7zip";                      url = "https://www.7-zip.org/a/7z2408-x64.exe"; out = "$env:TEMP\7zip.exe"; args = "/S" },
                @{ id = "VideoLAN.VLC";                   url = "https://get.videolan.org/vlc/3.0.21/win64/vlc-3.0.21-win64.exe"; out = "$env:TEMP\VLC.exe"; args = "/S" },
                @{ id = "AnyDeskSoftwareGmbH.AnyDesk";   url = "https://download.anydesk.com/AnyDesk.exe"; out = "$env:TEMP\AnyDesk.exe"; args = "--install `"C:\Program Files (x86)\AnyDesk`" --start-with-win --silent" },
                @{ id = "Zoom.Zoom";                      url = "https://zoom.us/client/latest/ZoomInstaller.exe"; out = "$env:TEMP\Zoom.exe"; args = "/silent" },
                @{ id = "Notion.Notion";                  url = "https://www.notion.so/desktop/windows/download"; out = "$env:TEMP\Notion.exe"; args = "/S" }
            )

            foreach ($app in $apps) {
                Write-Host "Installing $($app.id)..." -ForegroundColor Yellow
                
                $installed = $false
                $wingetRes = & winget install --id $app.id --silent --accept-package-agreements --accept-source-agreements --scope machine --override "/silent" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "      [OK] $($app.id) installed via Winget." -ForegroundColor Green
                    $installed = $true
                }
                
                if (-not $installed) {
                    Write-Host "      [Direct Download] Downloading from vendor..." -ForegroundColor Gray
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
                            Write-Host "      [OK] $($app.id) installed successfully." -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "      [WARN] Direct download failed for $($app.id): $_" -ForegroundColor Red
                    }
                }
            }
            Write-Host "`n[OK] Installation process completed." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "2" {
            Write-Host "`nApplying Windows 11 Tweaks..." -ForegroundColor Yellow
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
            Write-Host "`n[OK] Tweaks applied." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
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
            Write-Host "`nFixing Print Spooler..." -ForegroundColor Yellow
            Stop-Service spooler -ErrorAction SilentlyContinue
            Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service spooler -ErrorAction SilentlyContinue
            Write-Host "`n[OK] Print queue cleared." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "5" {
            Write-Host "`n=== Comprehensive Network Reset & Wi-Fi/TCP Performance Optimizer ===" -ForegroundColor Yellow
            
            # 1. Flush DNS & ARP Table
            Write-Host "      [1/6] Flushing DNS Cache & Clearing ARP Tables..." -ForegroundColor Gray
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            ipconfig /flushdns >$null 2>&1
            arp -d * >$null 2>&1

            # 2. Reset Winsock & TCP/IP Stack
            Write-Host "      [2/6] Resetting Winsock & TCP/IP Stack..." -ForegroundColor Gray
            netsh winsock reset >$null 2>&1
            netsh int ip reset >$null 2>&1
            netsh int tcp reset >$null 2>&1

            # 3. Optimize Windows TCP Stack (CUBIC Congestion, ECN, Window Auto-Tuning)
            Write-Host "      [3/6] Optimizing TCP Window Scaling & Congestion Provider (CUBIC)..." -ForegroundColor Gray
            Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Normal -ScalingHeuristics Disabled -EcnCapability Enabled -CongestionProvider CUBIC -ErrorAction SilentlyContinue
            Set-NetTCPSetting -SettingName InternetCustom -AutoTuningLevelLocal Normal -ScalingHeuristics Disabled -EcnCapability Enabled -CongestionProvider CUBIC -ErrorAction SilentlyContinue

            # 4. Universal Wi-Fi Adapter Tuning (Intel, Realtek, MediaTek, Qualcomm, Broadcom)
            Write-Host "      [4/6] Optimizing Wi-Fi settings across all vendor chipsets (Intel, Realtek, MediaTek, Qualcomm)..." -ForegroundColor Gray
            Get-NetAdapter -Name "Wi-Fi*", "Wireless*", "WLAN*" -ErrorAction SilentlyContinue | ForEach-Object {
                $adapterName = $_.Name
                $advProps = Get-NetAdapterAdvancedProperty -Name $adapterName -ErrorAction SilentlyContinue
                
                # A. Roaming Aggressiveness (Lowest / 1 / Disable)
                $roamProp = $advProps | Where-Object { $_.DisplayName -like "*Roaming*" -or $_.RegistryKeyword -in @("RegRoamLevel", "RoamAggressiveness", "RoamingAggressiveness") }
                if ($roamProp) {
                    $roamVal = $roamProp.ValidDisplayValues | Where-Object { $_ -like "1.*" -or $_ -like "*Lowest*" -or $_ -like "*Disabled*" -or $_ -eq "1" } | Select-Object -First 1
                    if ($roamVal) { Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $roamProp.DisplayName -DisplayValue $roamVal -ErrorAction SilentlyContinue }
                }

                # B. Preferred Band (5GHz / 5G first)
                $bandProp = $advProps | Where-Object { $_.DisplayName -like "*Preferred Band*" -or $_.DisplayName -like "*Band Preference*" -or $_.RegistryKeyword -in @("PreferBand", "PreferredBand") }
                if ($bandProp) {
                    $bandVal = $bandProp.ValidDisplayValues | Where-Object { $_ -like "*5G*" -or $_ -like "*5 GHz*" -or $_ -like "3.*" -or $_ -like "*Prefer 5*" } | Select-Object -First 1
                    if ($bandVal) { Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $bandProp.DisplayName -DisplayValue $bandVal -ErrorAction SilentlyContinue }
                }

                # C. Disable Power Saving / Sleep on Disconnect
                $powerProps = $advProps | Where-Object { $_.DisplayName -like "*Power Save*" -or $_.DisplayName -like "*Energy Efficient*" -or $_.RegistryKeyword -in @("MIMO_PS", "PowerSavingMode", "DeviceSleepOnDisconnect") }
                foreach ($p in $powerProps) {
                    $offVal = $p.ValidDisplayValues | Where-Object { $_ -like "*Disabled*" -or $_ -like "*Off*" -or $_ -eq "0" } | Select-Object -First 1
                    if ($offVal) { Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $p.DisplayName -DisplayValue $offVal -ErrorAction SilentlyContinue }
                }
            }

            # 5. Reset Windows Firewall Network Profiles
            Write-Host "      [5/6] Ensuring Network Discovery & ICMP Echo are active..." -ForegroundColor Gray
            netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >$null 2>&1
            netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes >$null 2>&1

            # 6. Release & Renew DHCP
            Write-Host "      [6/6] Refreshing DHCP IP Leases..." -ForegroundColor Gray
            ipconfig /renew >$null 2>&1

            Write-Host "`n[OK] Network Reset & Wi-Fi Performance Optimization completed successfully!" -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "6" {
            Write-Host "`n=== Manage Windows Auto-Update ===" -ForegroundColor Yellow
            Write-Host "   [1] Pause Windows Auto-Update for 9999 Days (~27 Years)" -ForegroundColor Red
            Write-Host "   [2] Resume / Restore Windows Auto-Update" -ForegroundColor Green
            Write-Host ""
            $updateChoice = Read-Host "Select option (1-2)"

            if ($updateChoice -eq "1") {
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
            } else {
                Write-Host "`n[WARN] Invalid choice. No changes were made." -ForegroundColor Yellow
            }

            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
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
            $deployUser = "AsetDP"
            $deployPass = ConvertTo-SecureString "@AsetDP25" -AsPlainText -Force
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
            Write-Host "      [OK] WMI, RPC, Remote UAC, and Remote Administration enabled." -ForegroundColor Green
            Write-Host "      [OK] Remote Registry and WMI services started." -ForegroundColor Green

            # 2. Silent Install LsAgent if present
            $localLsAgent1 = "D:\Sharing\Software\LsAgent-windows.exe"
            $localLsAgent2 = "C:\Program Files (x86)\Lansweeper\Client\LsAgent-windows.exe"
            $uncLsAgent1   = "\\192.168.10.160\Sharing\Software\LsAgent-windows.exe"
            $uncLsAgent2   = "\\192.168.10.160\DefaultPackageShare$\Client\LsAgent-windows.exe"
            $agentArgs     = "--mode unattended --agentkey 7e60329b-2a26-4337-b711-4df5b8964a76 --server 192.168.10.160 --port 9524"

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

            # Connect network share using dedicated read-only service account if needed
            net use "\\192.168.10.160\Sharing" "Ls@Deploy2026!" /user:"192.168.10.160\ls_deploy" >$null 2>&1
            net use "\\192.168.10.160\DefaultPackageShare$" "Ls@Deploy2026!" /user:"192.168.10.160\ls_deploy" >$null 2>&1

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
            } elseif (Test-Path $uncLsAgent1) {
                Write-Host "      [Network Share] Installing LsAgent silently via network share..." -ForegroundColor Gray
                $proc = Start-Process -FilePath $uncLsAgent1 -ArgumentList $agentArgs -PassThru
                $proc.WaitForExit()
                Write-Host "      [OK] LsAgent installed successfully via network share." -ForegroundColor Green
            } elseif (Test-Path $uncLsAgent2) {
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
            $sourceChoice = Read-Host "Select source (1-4) [Default: 1]"
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

            # Connect network share using dedicated read-only service account
            net use "\\192.168.10.160\Sharing" "Ls@Deploy2026!" /user:"192.168.10.160\ls_deploy" >$null 2>&1

            $localInstaller = "D:\Sharing\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
            $uncInstaller   = "\\192.168.10.160\Sharing\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe"
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
            Write-Host "`nApplying Universal AutoCAD Telemetry & Genuine License Blocker..." -ForegroundColor Yellow
            
            # 1. Stop & Disable Autodesk Genuine & Licensing Services
            Write-Host "      [1/4] Stopping Autodesk Genuine & Licensing Services..." -ForegroundColor Gray
            Stop-Service -Name "Autodesk Genuine Service", "AdskLicensingService", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "Autodesk Genuine Service" -StartupType Disabled -ErrorAction SilentlyContinue
            Set-Service -Name "AdAppMgr-Service" -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Process -Name "GenuineService", "AdskLicensingAgent", "AdskIdentityManager", "AutodeskDesktopApp", "AdAppMgr-Service" -Force -ErrorAction SilentlyContinue

            # 2. Dynamic Search & Block for All AutoCAD Versions (2016-2027+)
            Write-Host "      [2/4] Scanning & Blocking Firewall for all installed AutoCAD versions..." -ForegroundColor Gray
            $acadPaths = @(
                Get-ChildItem -Path "C:\Program Files\Autodesk", "C:\Program Files (x86)\Autodesk" -Filter "acad.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            )
            
            # Default known static binaries
            $staticBinaries = @(
                "C:\Program Files\Autodesk\Autodesk Genuine Service\GenuineService.exe",
                "C:\Program Files\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingAgent\AdskLicensingAgent.exe",
                "C:\Program Files (x86)\Autodesk\Autodesk Desktop App\AutodeskDesktopApp.exe",
                "C:\Program Files (x86)\Common Files\Autodesk Shared\AppManager\R1\AdAppMgr-Service.exe",
                "C:\Program Files\Common Files\Autodesk Shared\AdLM\R14\LTU.exe",
                "C:\Program Files\Common Files\Autodesk Shared\AdLM\R15\LTU.exe"
            )

            $allTargets = ($acadPaths + $staticBinaries) | Select-Object -Unique

            foreach ($bin in $allTargets) {
                if (Test-Path $bin) {
                    $bName = (Get-Item $bin).BaseName
                    $pDir = (Get-Item $bin).Directory.Name
                    $ruleName = "Block Autodesk ($pDir - $bName)"
                    
                    netsh advfirewall firewall delete rule name="$ruleName Outbound" >$null 2>&1
                    netsh advfirewall firewall delete rule name="$ruleName Inbound" >$null 2>&1
                    netsh advfirewall firewall add rule name="$ruleName Outbound" dir=out action=block program="$bin" enable=yes >$null 2>&1
                    netsh advfirewall firewall add rule name="$ruleName Inbound" dir=in action=block program="$bin" enable=yes >$null 2>&1
                    Write-Host "         [Blocked] $bin" -ForegroundColor DarkGray
                }
            }

            # 3. Add Telemetry & Genuine Check Domains to Hosts file
            Write-Host "      [3/4] Blocking Autodesk telemetry domains in Hosts file..." -ForegroundColor Gray
            $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
            Unblock-File -Path $hostsPath -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $hostsPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            
            $domainsToBlock = @(
                "127.0.0.1 genuine-software2.autodesk.com",
                "127.0.0.1 genuine-software.autodesk.com",
                "127.0.0.1 ipm-provider.autodesk.com",
                "127.0.0.1 api.autodesk.com",
                "127.0.0.1 developer.api.autodesk.com",
                "127.0.0.1 curson.autodesk.com",
                "127.0.0.1 registeronce.autodesk.com",
                "127.0.0.1 asset-direct.autodesk.com",
                "127.0.0.1 analytics.autodesk.com",
                "127.0.0.1 clm.autodesk.com",
                "127.0.0.1 lic.autodesk.com",
                "127.0.0.1 access.clm.autodesk.com",
                "127.0.0.1 genuine-software1.autodesk.com"
            )
            
            $existingHosts = Get-Content $hostsPath -ErrorAction SilentlyContinue
            foreach ($entry in $domainsToBlock) {
                if ($existingHosts -notcontains $entry) {
                    Add-Content -Path $hostsPath -Value $entry -ErrorAction SilentlyContinue
                }
            }

            # 4. IFEO Debugger Block & Flush DNS
            Write-Host "      [4/4] Setting IFEO block and flushing DNS cache..." -ForegroundColor Gray
            $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GenuineService.exe"
            if (-not (Test-Path $ifeoPath)) { New-Item -Path $ifeoPath -Force | Out-Null }
            Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "systray.exe" -Force -ErrorAction SilentlyContinue
            
            Clear-DnsClientCache -ErrorAction SilentlyContinue

            Write-Host "`n[OK] Universal AutoCAD Genuine & License Blocker applied successfully!" -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
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

            if ($scanChoice -match '^\d+$' -and [int]$scanChoice -ge 1 -and [int]$scanChoice -le $subnets.Count) {
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
            } elseif ($scanChoice -eq '0') {
                # Return to menu
                continue
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
        "0" { 
            exit 
        }
        default {
            Write-Host "`n[ERROR] Invalid option." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
