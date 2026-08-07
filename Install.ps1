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
    Write-Host "                    IT SUPPORT TOOLKIT - MAIN MENU                       " -ForegroundColor Cyan
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1] Install Standard Apps (WhatsApp, Chrome, Acrobat, 7-Zip, AnyDesk, Zoom)"
    Write-Host "   [2] Apply Windows 11 Tweaks (Dark Mode, File Explorer, End Task & Privacy)"
    Write-Host "   [3] Repair System Corruption (SFC & DISM RestoreHealth)"
    Write-Host "   [4] Repair Print Spooler Queue"
    Write-Host "   [5] Network Reset & Flush DNS"
    Write-Host "   [6] Block Windows Auto-Update"
    Write-Host "   [7] Fix Lansweeper Access (Enable Remote Mgmt, Firewall & Install LsAgent)"
    Write-Host "   [8] Install Kaspersky Endpoint Security 14.0 (Silent)"
    Write-Host ""
    Write-Host "   [0] Exit" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Select option (0-8)"

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
            Write-Host "`nResetting Network..." -ForegroundColor Yellow
            ipconfig /flushdns
            netsh winsock reset
            netsh int ip reset
            Write-Host "`n[OK] Network reset completed." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "6" {
            Write-Host "`nBlocking Windows Update..." -ForegroundColor Yellow
            sc config wuauserv start= disabled ; Stop-Service wuauserv -ErrorAction SilentlyContinue
            reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >$null 2>&1
            Write-Host "`n[OK] Windows Update blocked." -ForegroundColor Green
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

            # 0. Deep Clean Incompatible Antivirus Remnants (360, AVG, Avast, Smadav, McAfee, Norton) from WMI & Registry
            Write-Host "      [Cleaning] Purging leftover third-party Antivirus remnants (AVG, Avast, 360, Smadav, McAfee)..." -ForegroundColor Gray
            
            # Stop and remove leftover services
            $avPatterns = '*360*', '*Qihu*', '*ZhuDong*', '*AVG*', '*Avast*', '*Smadav*', '*McAfee*', '*Norton*', '*Symantec*'
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
                "HKLM:\SOFTWARE\McAfee", "HKLM:\SOFTWARE\WOW6432Node\McAfee"
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

            switch ($sourceChoice) {
                "2" {
                    if ($fdInstaller) {
                        Write-Host "      [Flash Drive] Launching Kaspersky installer ($fdInstaller)..." -ForegroundColor Gray
                        $proc = Start-Process -FilePath $fdInstaller -Wait -PassThru
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "      [ERROR] Installer not found on any connected Flash Drive (USB)." -ForegroundColor Red
                    }
                }
                "3" {
                    if (Test-Path $localInstaller) {
                        Write-Host "      [Local] Launching Kaspersky installer..." -ForegroundColor Gray
                        $proc = Start-Process -FilePath $localInstaller -Wait -PassThru
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "      [ERROR] Local installer not found at $localInstaller." -ForegroundColor Red
                    }
                }
                "4" {
                    if (Test-Path $uncInstaller) {
                        Write-Host "      [Network Share] Copying installer to local temp (BITS / SMB)..." -ForegroundColor Gray
                        $tempInstaller = "$env:TEMP\KES14_Setup.exe"
                        
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

                        if ($copySuccess -and (Test-Path $tempInstaller)) {
                            Write-Host "      [Network Share] Launching Kaspersky installer..." -ForegroundColor Gray
                            $proc = Start-Process -FilePath $tempInstaller -Wait -PassThru
                            Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue
                            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                                Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                            } else {
                                Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "      [ERROR] Failed to copy installer from network share. Launching directly..." -ForegroundColor Red
                            $proc = Start-Process -FilePath $uncInstaller -Wait -PassThru
                            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                                Write-Host "      [OK] Kaspersky task completed." -ForegroundColor Green
                            } else {
                                Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                            }
                        }
                    } else {
                        Write-Host "      [ERROR] Network share installer not found at $uncInstaller." -ForegroundColor Red
                    }
                }
                default {
                    # Auto-Detect mode
                    if ($fdInstaller) {
                        Write-Host "      [Flash Drive] Launching Kaspersky installer ($fdInstaller)..." -ForegroundColor Gray
                        $proc = Start-Process -FilePath $fdInstaller -Wait -PassThru
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                        }
                    } elseif (Test-Path $localInstaller) {
                        Write-Host "      [Local] Launching Kaspersky installer..." -ForegroundColor Gray
                        $proc = Start-Process -FilePath $localInstaller -Wait -PassThru
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                            Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                        } else {
                            Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                        }
                    } elseif (Test-Path $uncInstaller) {
                        Write-Host "      [Network Share] Copying installer to local temp (BITS / SMB)..." -ForegroundColor Gray
                        $tempInstaller = "$env:TEMP\KES14_Setup.exe"
                        
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

                        if ($copySuccess -and (Test-Path $tempInstaller)) {
                            Write-Host "      [Network Share] Launching Kaspersky installer..." -ForegroundColor Gray
                            $proc = Start-Process -FilePath $tempInstaller -Wait -PassThru
                            Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue
                            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                                Write-Host "      [OK] Kaspersky Endpoint Security installed successfully." -ForegroundColor Green
                            } else {
                                Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "      [ERROR] Failed to copy installer from network share. Launching directly..." -ForegroundColor Red
                            $proc = Start-Process -FilePath $uncInstaller -Wait -PassThru
                            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                                Write-Host "      [OK] Kaspersky task completed." -ForegroundColor Green
                            } else {
                                Write-Host "      [ERROR] Kaspersky installation finished or closed (ExitCode: $($proc.ExitCode))." -ForegroundColor Red
                            }
                        }
                    } else {
                        Write-Host "      [ERROR] Kaspersky installer not found at local, USB, or network share path." -ForegroundColor Red
                    }
                }
            }
            Write-Host "`n[OK] Kaspersky task completed." -ForegroundColor Green
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
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
