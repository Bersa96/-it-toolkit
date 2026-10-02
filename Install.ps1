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

function Get-ToolkitPerformanceHardware {
    $drive = $env:SystemDrive.TrimEnd(':')
    $media = 'Unknown'
    $bus = 'Unknown'
    try {
        $disk = Get-Partition -DriveLetter $drive -ErrorAction Stop | Get-Disk -ErrorAction Stop
        $bus = [string]$disk.BusType
        if ($bus -eq 'NVMe') { $media = 'SSD' }
        else {
            # Match by storage association; never assume disk numbers equal PhysicalDisk DeviceId.
            $physical = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object {
                ($_.UniqueId -and $_.UniqueId -eq $disk.UniqueId) -or
                ($_.SerialNumber -and $disk.SerialNumber -and $_.SerialNumber.Trim() -eq $disk.SerialNumber.Trim())
            })
            if ($physical.Count -eq 1 -and [string]$physical[0].MediaType -in @('SSD','HDD')) {
                $media = [string]$physical[0].MediaType
            }
        }
    } catch { Write-Host '[WARN] Storage type unavailable; no HDD/SSD assumptions will be made.' -ForegroundColor Yellow }
    $ram = $null
    try { $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) } catch {}
    [pscustomobject]@{ Drive = $drive; Media = $media; Bus = $bus; RAMGB = $ram }
}

function Invoke-ToolkitPerformanceProfile {
    param([string]$Profile)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $backupDir = Join-Path $env:ProgramData 'ITToolkit\Performance'
    $backupFile = Join-Path $backupDir "settings-$sid.xml"
    $specs = @(
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='StartupBoostEnabled'; Kind='DWord'; Value=0; Group='Memory' },
        @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='BackgroundModeEnabled'; Kind='DWord'; Value=0; Group='Memory' },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Kind='DWord'; Value=0; Group='Visual' },
        @{ Path='HKCU:\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Kind='String'; Value='0'; Group='Visual' },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAnimations'; Kind='DWord'; Value=0; Group='Visual' },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='HideFileExt'; Kind='DWord'; Value=0; Group='UI' },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='LaunchTo'; Kind='DWord'; Value=1; Group='UI' }
    )
    $state = @()
    if (Test-Path -LiteralPath $backupFile) { $state = @(Import-Clixml -LiteralPath $backupFile -ErrorAction Stop) }
    if ($Profile -eq 'Restore') {
        if (-not $state.Count) { throw 'No saved tuning baseline exists for this user. Legacy tuning cannot be reconstructed automatically.' }
        $restoreFailed = $false
        foreach ($entry in $state) {
            try {
                if ($entry.Exists) {
                    New-Item -Path $entry.Path -Force -ErrorAction Stop | Out-Null
                    New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind -Force -ErrorAction Stop | Out-Null
                } elseif (Test-Path -LiteralPath $entry.Path) {
                    $key = Get-Item -LiteralPath $entry.Path -ErrorAction Stop
                    if ($key.GetValueNames() -contains $entry.Name) { Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop }
                }
            } catch { $restoreFailed = $true; Write-Host "[ERROR] Restore $($entry.Name): $_" -ForegroundColor Red }
        }
        if ($restoreFailed) { throw 'Rollback incomplete; baseline retained so you can retry.' }
        # Keep the immutable baseline for subsequent verification/retry.
        Write-Host "[OK] Saved settings restored. Baseline: $backupFile" -ForegroundColor Green
        return
    }
    $hw = Get-ToolkitPerformanceHardware
    $groups = switch ($Profile) {
        'Smart' { 'Memory'; if ($null -ne $hw.RAMGB -and $hw.RAMGB -le 8) { 'Visual' } }
        'Memory' { 'Memory' }
        'Visual' { 'Visual' }
        'UI' { 'UI' }
        default { throw 'Unknown tuning profile.' }
    }
    $changes = @($specs | Where-Object { $_.Group -in $groups })
    Write-Host 'Pagefile, SysMain, Prefetch, telemetry, GameDVR and Windows drive optimization schedules are left unchanged.'
    Write-Host 'Memory profile disables Edge background operation; background browser apps/notifications may stop. HKCU changes apply to the account running this elevated toolkit.' -ForegroundColor Yellow
    $changes | ForEach-Object { Write-Host "  $($_.Path) / $($_.Name) = $($_.Value)" }
    if ((Read-Host 'Apply these changes? Type YES') -cne 'YES') { Write-Host '[CANCELLED]'; return }
    # Persist every original value before any registry mutation; never overwrite a previous baseline.
    foreach ($spec in $changes) {
        if (@($state | Where-Object { $_.Path -eq $spec.Path -and $_.Name -eq $spec.Name }).Count) { continue }
        $key = Get-Item -LiteralPath $spec.Path -ErrorAction SilentlyContinue
        $exists = $key -and ($key.GetValueNames() -contains $spec.Name)
        $state += [pscustomobject]@{
            Path=$spec.Path; Name=$spec.Name; Exists=[bool]$exists
            Kind=$(if ($exists) { [string]$key.GetValueKind($spec.Name) } else { $spec.Kind })
            Value=$(if ($exists) { $key.GetValue($spec.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null })
        }
    }
    New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
    $pending = "$backupFile.$([guid]::NewGuid().ToString('N')).tmp"
    $state | Export-Clixml -LiteralPath $pending -ErrorAction Stop
    Move-Item -LiteralPath $pending -Destination $backupFile -Force -ErrorAction Stop
    $failed = $false
    foreach ($spec in $changes) {
        try {
            New-Item -Path $spec.Path -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $spec.Path -Name $spec.Name -Value $spec.Value -PropertyType $spec.Kind -Force -ErrorAction Stop | Out-Null
            if ((Get-ItemPropertyValue -LiteralPath $spec.Path -Name $spec.Name -ErrorAction Stop) -ne $spec.Value) { throw 'Verification mismatch.' }
            Write-Host "[OK] $($spec.Name) verified." -ForegroundColor Green
        } catch { $failed = $true; Write-Host "[ERROR] $($spec.Name): $_" -ForegroundColor Red }
    }
    if ($failed) { throw "Some changes failed; use Restore saved settings. Baseline: $backupFile" }
    Write-Host "[OK] Profile verified. Baseline: $backupFile. Sign out/in when convenient; Explorer is not forcibly terminated." -ForegroundColor Green
}

function Show-ToolkitPerformanceMenu {
    while ($true) {
        $hw = Get-ToolkitPerformanceHardware
        Write-Host "`nPERFORMANCE: System drive $($hw.Drive): | $($hw.Media) / $($hw.Bus) | RAM $($hw.RAMGB) GB" -ForegroundColor Cyan
        Write-Host '[1] Conservative Smart profile (Edge background; animations only at <=8GB RAM)'
        Write-Host '[2] Analyze system volume (read-only; no forced HDD service changes)'
        Write-Host '[3] Optimize system volume using Windows media-aware defaults'
        Write-Host '[4] Memory profile (Edge background only; pagefile unchanged)'
        Write-Host '[5] Reduce UI animations and transparency'
        Write-Host '[6] Explorer preferences (extensions and This PC)'
        Write-Host '[7] Preview optional apps for removal (current user only)'
        Write-Host '[8] Restore saved tuning settings (not legacy settings/app removals)'
        Write-Host '[0] Back'
        $choice = Read-Host 'Select 0-8'
        if ($choice -eq '0') { return }
        try {
            switch ($choice) {
                '1' { Invoke-ToolkitPerformanceProfile 'Smart' }
                '2' { Optimize-Volume -DriveLetter $hw.Drive -Analyze -Verbose -ErrorAction Stop }
                '3' {
                    if ((Read-Host 'Run Windows volume optimization now? May create disk load. Type YES') -ceq 'YES') {
                        Optimize-Volume -DriveLetter $hw.Drive -Verbose -ErrorAction Stop
                        Write-Host '[OK] Windows volume optimization completed.' -ForegroundColor Green
                    }
                }
                '4' { Invoke-ToolkitPerformanceProfile 'Memory' }
                '5' { Invoke-ToolkitPerformanceProfile 'Visual' }
                '6' { Invoke-ToolkitPerformanceProfile 'UI' }
                '7' {
                    $candidates = @(Get-AppxPackage -ErrorAction Stop | Where-Object {
                        $_.Name -match '^(king\.com\.(CandyCrush.*|BubbleWitch.*|FarmHeroes.*)|Microsoft\.BingNews|Microsoft\.BingWeather)$'
                    })
                    if (-not $candidates.Count) { Write-Host '[INFO] No optional apps found.'; break }
                    $candidates | ForEach-Object { Write-Host "  $($_.Name)" }
                    Write-Host 'Removes these apps for the current user only, not provisioned packages or other users. NOT reversible by tuning rollback; reinstall from Store if needed.' -ForegroundColor Yellow
                    if ((Read-Host 'Remove exactly this list? Type REMOVE') -ceq 'REMOVE') {
                        foreach ($app in $candidates) {
                            try {
                                Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
                                if (Get-AppxPackage -Name $app.Name -ErrorAction Stop) { throw 'Package still present.' }
                                Write-Host "[OK] Removed $($app.Name)" -ForegroundColor Green
                            } catch { Write-Host "[ERROR] Removal $($app.Name): $_" -ForegroundColor Red }
                        }
                    }
                }
                '8' { Invoke-ToolkitPerformanceProfile 'Restore' }
                default { Write-Host '[WARN] Invalid selection.' -ForegroundColor Yellow }
            }
        } catch { Write-Host "[ERROR] Tuning incomplete: $_" -ForegroundColor Red }
        Read-Host 'Press Enter to continue' | Out-Null
    }
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

function Set-ToolkitDeviceIdentity {
    param([string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Identity)) { return $false }
    try {
        $description = $Identity.Trim().ToUpperInvariant()
        if ($description -notmatch '^[A-Z0-9][A-Z0-9-]*[A-Z0-9]$') {
            throw 'Use letters, numbers and hyphens only (no leading/trailing hyphen).'
        }
        $hostname = $description
        if ($hostname.Length -gt 15) {
            if ($description -match '^(.+?-DOK)(?:-|$)' -and $Matches[1].Length -le 15) {
                $hostname = $Matches[1]
            } else {
                $hostname = (Read-Host 'Full description exceeds 15 characters. Enter a unique short Windows hostname').Trim().ToUpperInvariant()
            }
        }
        if ($hostname.Length -gt 15 -or $hostname -notmatch '^[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?$' -or $hostname -match '^\d+$') {
            throw 'Windows hostname must be 1-15 characters, not all numeric, with no leading/trailing hyphen.'
        }
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($computer.PartOfDomain) { throw 'Domain-joined computer: coordinate rename with the domain administrator.' }
        $pendingPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'
        $pending = (Get-ItemProperty -Path $pendingPath -ErrorAction Stop).ComputerName
        if ($pending -ne $hostname) {
            Rename-Computer -NewName $hostname -Force -ErrorAction Stop
        }
        $verified = (Get-ItemProperty -Path $pendingPath -ErrorAction Stop).ComputerName
        if ($verified -ne $hostname) { throw 'Requested hostname was not retained by Windows.' }
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters' -Name 'srvcomment' -Value $description -ErrorAction Stop
        Write-Host "      [OK] Verified pending hostname: $hostname; description: $description" -ForegroundColor Green
        if ($computer.Name -ne $hostname) {
            Write-Host "      [REBOOT REQUIRED] Active hostname is still $($computer.Name). Save work and reboot manually." -ForegroundColor Yellow
        }
        Write-Host '      [LAN SWEEPER] AssetName/UserDomain update after reboot and a successful fresh scan. FullName does not rename the login account or profile.' -ForegroundColor Yellow
        return $true
    } catch {
        Write-Host "      [ERROR] Device identity update failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-ToolkitLocalAccountDisplayName {
    Write-Host "`nOptional: update a local account's display/full name (does not rename the account or profile folder)." -ForegroundColor Cyan
    $accountName = (Read-Host 'Local username to update [Press Enter to skip]').Trim()
    if ([string]::IsNullOrWhiteSpace($accountName)) {
        Write-Host '      [SKIPPED] Local account display name was not changed.' -ForegroundColor Gray
        return $false
    }

    try {
        $account = Get-LocalUser -Name $accountName -ErrorAction Stop
        $displayName = (Read-Host "Display/full name for '$($account.Name)' [Press Enter to skip]").Trim()
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            Write-Host '      [SKIPPED] Local account display name was not changed.' -ForegroundColor Gray
            return $false
        }

        Set-LocalUser -Name $account.Name -FullName $displayName -ErrorAction Stop | Out-Null
        $updatedAccount = Get-LocalUser -Name $account.Name -ErrorAction Stop
        if ($updatedAccount.FullName -ne $displayName) {
            throw 'Windows did not retain the requested display/full name.'
        }
        Write-Host "      [OK] Local account '$($account.Name)' display/full name set to '$displayName'." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      [ERROR] Could not update the local account display/full name: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '      This setting applies to local Windows accounts only; domain accounts are not modified.' -ForegroundColor Yellow
        return $false
    }
}

function Install-ToolkitAgent {
    param([string]$Installer, [string]$Arguments, [string]$ServiceName, [string]$SourceLabel = 'Installer source')
    $stage = Join-Path "$env:SystemDrive\Temp" ('ToolkitAgent-' + [guid]::NewGuid().ToString('N'))
    $stagedExe = Join-Path $stage ([System.IO.Path]::GetFileName($Installer))
    $partialExe = "$stagedExe.partial"
    $copyVerified = $false
    $retainStage = $false
    try {
        New-Item -ItemType Directory -Path $stage -Force -ErrorAction Stop | Out-Null
        $sourceFile = Get-Item -LiteralPath $Installer -ErrorAction Stop
        if ($sourceFile.Length -le 0) { throw 'Installer source is empty.' }
        Write-Host "      [$SourceLabel] Copying $($sourceFile.Name) to $stage ..." -ForegroundColor Gray
        Copy-Item -LiteralPath $Installer -Destination $partialExe -ErrorAction Stop
        $copiedFile = Get-Item -LiteralPath $partialExe -ErrorAction Stop
        $sourceHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256 -ErrorAction Stop).Hash
        $copiedHash = (Get-FileHash -LiteralPath $partialExe -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($copiedFile.Length -ne $sourceFile.Length -or $copiedHash -ne $sourceHash) {
            throw 'The staged installer does not match the source file (size/SHA-256 verification failed).'
        }
        Move-Item -LiteralPath $partialExe -Destination $stagedExe -ErrorAction Stop
        $copyVerified = $true
        Write-Host '      [OK] Installer copied and SHA-256 verified. USB can now be ejected.' -ForegroundColor Green
        Write-Host "      [Executing] Launching the verified local copy: $stagedExe" -ForegroundColor Yellow
        $process = Start-Process -FilePath $stagedExe -ArgumentList $Arguments -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -eq 3010) {
            Write-Host '[PENDING] Installer returned 3010 and requires a reboot; no reboot was triggered.' -ForegroundColor Yellow
            return $false
        }
        if ($process.ExitCode -ne 0) { throw "Installer exit code: $($process.ExitCode)" }
        $service = if ($ServiceName -eq 'LansweeperAgentService') {
            Get-ToolkitLsAgentService
        } else {
            Get-Service -Name $ServiceName -ErrorAction Stop
        }
        if (-not $service) { throw "The expected service '$ServiceName' was not found after installation." }
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Start-Service -Name $service.Name -ErrorAction Stop
        }
        $service = Get-Service -Name $service.Name -ErrorAction Stop
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
        if ($ServiceName -eq 'LansweeperAgentService') {
            Repair-ToolkitLsAgentService | Out-Null
        }
        Write-Host "[OK] $($service.DisplayName) is installed and running. Server check-in still requires verification." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[ERROR] Agent installation not verified: $($_.Exception.Message)" -ForegroundColor Red
        if ($copyVerified -and (Test-Path -LiteralPath $stagedExe -PathType Leaf)) {
            $retainStage = $true
            Write-Host "      [DIAGNOSTIC] Verified installer retained at $stagedExe" -ForegroundColor Yellow
        }
        return $false
    } finally {
        if (Test-Path -LiteralPath $partialExe) { Remove-Item -LiteralPath $partialExe -Force -ErrorAction SilentlyContinue }
        if (-not $retainStage -and (Test-Path -LiteralPath $stage)) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Find-ToolkitUsbInstaller {
    param([Parameter(Mandatory = $true)][string]$FileName)

    $driveLetters = @()
    if ($PSScriptRoot) {
        try {
            $scriptDrive = (Get-Item -LiteralPath $PSScriptRoot -ErrorAction Stop).PSDrive.Name
            $scriptVolume = Get-Volume -DriveLetter $scriptDrive -ErrorAction SilentlyContinue
            if ($scriptVolume.DriveType -eq 'Removable') { $driveLetters += $scriptDrive }
        } catch { }
    }
    $driveLetters += Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
        Select-Object -ExpandProperty DriveLetter
    $driveLetters = @($driveLetters | Where-Object { $_ } | Select-Object -Unique)
    $folders = @('software\Software', 'Software', 'software\soft', 'soft', 'software', '')

    foreach ($driveLetter in $driveLetters) {
        $root = '{0}:\' -f $driveLetter
        foreach ($folder in $folders) {
            $basePath = if ($folder) { Join-Path $root $folder } else { $root }
            $candidate = Join-Path $basePath $FileName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
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

function Set-ToolkitClientAdministrator {
    param([Parameter(Mandatory=$true)][string]$UserName,
          [Parameter(Mandatory=$true)][securestring]$Password)
    try {
        $account = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
        if (-not $account) {
            New-LocalUser -Name $UserName -Password $Password -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null
        } else {
            Set-LocalUser -Name $UserName -Password $Password -PasswordNeverExpires $true -AccountNeverExpires -ErrorAction Stop
        }
        Enable-LocalUser -Name $UserName -ErrorAction Stop
        $account = Get-LocalUser -Name $UserName -ErrorAction Stop
        # SID works on both English and Indonesian Windows installations.
        $admins = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $members = @(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop)
        if ($account.SID.Value -notin @($members | ForEach-Object { $_.SID.Value })) {
            Add-LocalGroupMember -Group $admins.Name -Member "$env:COMPUTERNAME\$UserName" -ErrorAction Stop
        }
        $members = @(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop)
        if (-not $account.Enabled -or $account.SID.Value -notin @($members | ForEach-Object { $_.SID.Value })) {
            throw 'Account enablement or administrator membership was not retained.'
        }
        Write-Host "      [OK] Verified local administrator: $UserName (enabled, password updated)." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      [ERROR] Local administrator setup failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Enable-ToolkitRemoteInventoryAccess {
    param([string]$ServerAddress='192.168.10.160')
    $success = $true
    try {
        $path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        New-ItemProperty -Path $path -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        if ((Get-ItemProperty -Path $path -ErrorAction Stop).LocalAccountTokenFilterPolicy -ne 1) { throw 'Remote UAC policy verification failed.' }
        # Restrict toolkit-managed inbound permissions to the scanning server.
        $definitions=@(
            @{Name='ITToolkit-Lansweeper-SMB'; Port='445'; Service='LanmanServer'},
            @{Name='ITToolkit-Lansweeper-RPC'; Port='135'; Service='RpcSs'},
            @{Name='ITToolkit-Lansweeper-WMI'; Port='RPC'; Service='Winmgmt'}
        )
        foreach($definition in $definitions) {
            $existing=Get-NetFirewallRule -Name $definition.Name -ErrorAction SilentlyContinue
            if ($existing) { Remove-NetFirewallRule -Name $definition.Name -ErrorAction Stop }
            New-NetFirewallRule -Name $definition.Name -DisplayName $definition.Name -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalPort $definition.Port -Service $definition.Service -RemoteAddress $ServerAddress -ErrorAction Stop | Out-Null
            $rule=Get-NetFirewallRule -Name $definition.Name -ErrorAction Stop
            $scope=$rule | Get-NetFirewallAddressFilter -ErrorAction Stop
            if ([string]$rule.Enabled -ne 'True' -or [string]$rule.Action -ne 'Allow' -or $ServerAddress -notin @($scope.RemoteAddress)) { throw "Firewall verification failed: $($definition.Name)" }
        }
    } catch {
        $success=$false
        Write-Host "      [ERROR] Remote access policy/firewall: $($_.Exception.Message)" -ForegroundColor Red
    }
    foreach($name in @('LanmanServer','winmgmt','RemoteRegistry')) {
        try {
            Set-Service -Name $name -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $name -ErrorAction Stop
            $service=Get-Service -Name $name -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(30))
        } catch {
            $success=$false
            Write-Host "      [ERROR] Service ${name}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if($success) {
        Write-Host "      [OK] Local SMB/WMI setup verified; inbound rules scoped to $ServerAddress." -ForegroundColor Green
        Write-Host '      [NEXT] Verify remote login from Lansweeper. Wi-Fi isolation, routing, third-party firewall and scanning credentials require separate checks.' -ForegroundColor Yellow
    }
    return $success
}

function Get-ToolkitLsAgentService {
    # LsAgent service names vary slightly between Lansweeper installer builds.
    foreach ($name in @('LansweeperAgentService', 'LsAgent')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) { return $service }
    }
    return Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '(?i)LsAgent|Lansweeper.*Agent' } |
        Select-Object -First 1
}

function Test-ToolkitLsAgentServer {
    param(
        [string]$Server = '192.168.10.160',
        [int]$Port = 9524
    )
    try {
        return [bool](Test-NetConnection -ComputerName $Server -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Repair-ToolkitLsAgentConfiguration {
    param(
        [string]$Server = '192.168.10.160',
        [int]$Port = 9524
    )

    $configPaths = @(
        (Join-Path ${env:ProgramFiles(x86)} 'LansweeperAgent\LsAgent.ini'),
        (Join-Path $env:ProgramFiles 'LansweeperAgent\LsAgent.ini'),
        (Join-Path ${env:ProgramFiles(x86)} 'Lansweeper\Client\LsAgent.ini'),
        (Join-Path $env:ProgramFiles 'Lansweeper\Client\LsAgent.ini')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    $configPath = $configPaths | Select-Object -First 1
    if (-not $configPath) {
        Write-Host '      [INFO] LsAgent.ini was not found; installer defaults will be retained.' -ForegroundColor Gray
        return $false
    }

    try {
        $lines = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)
        $serverLine = $lines | Where-Object { $_ -match '^\s*Server\s*=' } | Select-Object -First 1
        $portLine = $lines | Where-Object { $_ -match '^\s*Port\s*=' } | Select-Object -First 1
        $currentServer = if ($serverLine) { ($serverLine -replace '^\s*Server\s*=\s*', '').Trim() } else { '' }
        $currentPort = if ($portLine) { ($portLine -replace '^\s*Port\s*=\s*', '').Trim() } else { '' }
        Write-Host "      [INFO] LsAgent.ini: Server=$currentServer Port=$currentPort" -ForegroundColor Gray

        if ($currentServer -eq $Server -and $currentPort -eq [string]$Port) { return $false }
        if (-not $serverLine -or -not $portLine) {
            Write-Host '      [WARN] LsAgent.ini format is not recognized; no file changes were made.' -ForegroundColor Yellow
            return $false
        }

        $backup = "$configPath.$(Get-Date -Format yyyyMMddHHmmss).bak"
        Copy-Item -LiteralPath $configPath -Destination $backup -ErrorAction Stop
        $updatedLines = $lines | ForEach-Object {
            if ($_ -match '^\s*Server\s*=') { "Server=$Server" }
            elseif ($_ -match '^\s*Port\s*=') { "Port=$Port" }
            else { $_ }
        }
        Set-Content -LiteralPath $configPath -Value $updatedLines -Encoding ascii -ErrorAction Stop
        Write-Host "      [OK] LsAgent.ini corrected to ${Server}:$Port. Backup: $backup" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      [WARN] Could not validate/update LsAgent.ini: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Repair-ToolkitLsAgentService {
    $service = Get-ToolkitLsAgentService
    if (-not $service) {
        Write-Host '      [INFO] LsAgent service is not installed.' -ForegroundColor Yellow
        return $false
    }

    try {
        $configChanged = Repair-ToolkitLsAgentConfiguration
        Set-Service -Name $service.Name -StartupType Automatic -ErrorAction Stop
        # Recover from a transient service crash without changing firewall or
        # authentication policy. The service restarts after 60s, then 5m.
        & sc.exe failure $service.Name reset= 86400 actions= restart/60000/restart/300000/none/0 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Service recovery configuration failed (sc.exe $LASTEXITCODE)." }
        & sc.exe failureflag $service.Name 1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Service recovery flag failed (sc.exe $LASTEXITCODE)." }
        if ($configChanged -and $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Restart-Service -Name $service.Name -Force -ErrorAction Stop
            $service = Get-Service -Name $service.Name -ErrorAction Stop
        } elseif ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Start-Service -Name $service.Name -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
        }
        $service=Get-Service -Name $service.Name -ErrorAction Stop
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(30))
        $transport = Test-ToolkitLsAgentServer
        Write-Host "      [OK] $($service.DisplayName) is Running (Automatic). Server 192.168.10.160:9524 reachable: $transport" -ForegroundColor Green
        if (-not $transport) {
            Write-Host '      [NEXT] Check routing/firewall to TCP 9524; the agent itself is running.' -ForegroundColor Yellow
        }
        return $true
    } catch {
        Write-Host "      [ERROR] Could not repair $($service.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}


function Find-ToolkitInstaller {
    param(
        [string[]]$Patterns,
        [string[]]$AdditionalPaths = @()
    )

    $searchDrives = @()
    if ($PSScriptRoot) {
        $sDrive = (Get-Item $PSScriptRoot -ErrorAction SilentlyContinue).PSDrive.Name
        if ($sDrive) { $searchDrives += $sDrive }
    }
    $searchDrives += (Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter)
    $searchDrives += (Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'C' } | Select-Object -ExpandProperty DriveLetter)
    $searchDrives = $searchDrives | Where-Object { $_ } | Select-Object -Unique

    $subFolders = @('software\Software', 'Software', 'software\soft', 'software', 'soft', '')
    $searchFolders = @()
    if ($PSScriptRoot) {
        $searchFolders += $PSScriptRoot
        $searchFolders += (Join-Path $PSScriptRoot 'software\Software')
        $searchFolders += (Join-Path $PSScriptRoot 'Software')
        $searchFolders += (Join-Path $PSScriptRoot 'software\soft')
        $searchFolders += (Join-Path $PSScriptRoot 'soft')
        $searchFolders += (Join-Path $PSScriptRoot 'software')
    }
    foreach ($d in $searchDrives) {
        foreach ($sf in $subFolders) {
            $folder = if ($sf) { "$($d):\$sf" } else { "$($d):\" }
            $searchFolders += $folder
        }
    }
    if ($AdditionalPaths) { $searchFolders += $AdditionalPaths }
    $searchFolders = $searchFolders | Select-Object -Unique

    foreach ($folder in $searchFolders) {
        if (Test-Path -LiteralPath $folder) {
            foreach ($pattern in $Patterns) {
                $found = Get-ChildItem -LiteralPath $folder -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    return $found.FullName
                }
            }
        }
    }
    return $null
}

function Get-ToolkitPrinterInventory {
    @(
        Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.Name
                Shared    = [bool]$_.Shared
                ShareName = $_.ShareName
                Driver    = $_.DriverName
                Port      = $_.PortName
                Status    = $_.PrinterStatus
            }
        }
    )
}

function Get-ToolkitDefaultPrinterShareName {
    param([Parameter(Mandatory = $true)][string]$PrinterName)

    $shareName = ($PrinterName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($shareName)) { $shareName = 'SharedPrinter' }
    if ($shareName.Length -gt 80) { $shareName = $shareName.Substring(0, 80).Trim() }
    return $shareName
}

function Test-ToolkitPrinterShareName {
    param([string]$ShareName)

    return -not [string]::IsNullOrWhiteSpace($ShareName) -and
        $ShareName -notmatch '[\\/:*?"<>|]' -and
        $ShareName -notmatch '^(\.|\.\.)$'
}

function Enable-ToolkitPrinterSharingFirewall {
    # Prefer the firewall cmdlets so we can avoid enabling printer sharing on
    # Public profiles. Fall back to netsh on older Windows builds.
    $rules = @(
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayGroup -match 'File\s+and\s+Printer\s+Sharing|Printer\s+Sharing' -or
                $_.Group -match 'FileAndPrinterSharing'
            }
    )
    if ($rules.Count -gt 0) {
        try {
            $rules | Set-NetFirewallRule -Enabled True -Profile Domain,Private -ErrorAction Stop
            return $true
        } catch {
            Write-Host "[WARN] Could not scope printer-sharing firewall rules to Domain/Private profiles: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >$null 2>&1
    if ($LASTEXITCODE -eq 0) { return $true }
    return $false
}

function Set-ToolkitPrinterShare {
    param(
        [Parameter(Mandatory = $true)][string]$PrinterName,
        [Parameter(Mandatory = $true)][string]$ShareName
    )

    if (-not (Test-ToolkitPrinterShareName -ShareName $ShareName)) {
        Write-Host '[ERROR] Invalid share name. Do not use \\, /, :, *, ?, " < > or |.' -ForegroundColor Red
        return $false
    }

    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (-not $printer) {
        Write-Host "[ERROR] Printer '$PrinterName' was not found on this PC." -ForegroundColor Red
        return $false
    }

    $conflict = Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.Shared -and $_.ShareName -eq $ShareName -and $_.Name -ne $PrinterName } |
        Select-Object -First 1
    if ($conflict) {
        Write-Host "[ERROR] Share name '$ShareName' is already used by '$($conflict.Name)'." -ForegroundColor Red
        return $false
    }

    try {
        $spooler = Get-Service -Name spooler -ErrorAction Stop
        if ($spooler.Status -ne 'Running') {
            Set-Service -Name spooler -StartupType Automatic -ErrorAction Stop
            Start-Service -Name spooler -ErrorAction Stop
        }
        Set-Printer -Name $PrinterName -Shared $true -ShareName $ShareName -ErrorAction Stop
        if (-not (Enable-ToolkitPrinterSharingFirewall)) {
            Write-Host '[WARN] Printer sharing was enabled, but the firewall rule could not be verified.' -ForegroundColor Yellow
        }

        $verify = Get-Printer -Name $PrinterName -ErrorAction Stop
        if (-not $verify.Shared -or $verify.ShareName -ne $ShareName) {
            throw 'Windows did not report the expected shared-printer state.'
        }
        Write-Host "[OK] Host printer share created: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Green
        Write-Host '     Clients can connect using the host name or a stable IP address.' -ForegroundColor Gray
        return $true
    } catch {
        Write-Host "[ERROR] Could not share printer '$PrinterName': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-ToolkitPrinterConnectionDiagnostic {
    param([string]$HostName, [string]$ShareName, [System.Management.Automation.ErrorRecord]$ConnectionError)
    if (-not $HostName) { $HostName = (Read-Host 'Nama atau IP PC host').Trim().Trim('\') }
    if (-not $ShareName) { $ShareName = (Read-Host 'Nama share printer').Trim() }
    if ($HostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or -not (Test-ToolkitPrinterShareName $ShareName)) {
        Write-Host '[ERROR] Nama host/share tidak valid.' -ForegroundColor Red; return
    }
    $connection = "\\$HostName\$ShareName"
    $report = [Collections.Generic.List[string]]::new()
    $report.Add("Printer diagnostic: $connection")
    $report.Add("Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $report.Add("Client: $env:COMPUTERNAME; user: $env:USERDOMAIN\$env:USERNAME")
    if ($ConnectionError) {
        $hex = '0x{0:X8}' -f ($ConnectionError.Exception.HResult -band 0xFFFFFFFFL)
        $report.Add("Connection error: $($ConnectionError.Exception.Message)")
        $report.Add("Exception HRESULT: $hex; ID: $($ConnectionError.FullyQualifiedErrorId)")
        if ($ConnectionError.Exception.PSObject.Properties['NativeErrorCode']) {
            $report.Add("Native error: $($ConnectionError.Exception.NativeErrorCode)")
        }
        $report.Add('HRESULT identifies the exception; it may differ from the underlying printer error. Keep the full message.')
    }
    try {
        $ips = @([Net.Dns]::GetHostAddresses($HostName) | ForEach-Object { $_.IPAddressToString })
        $report.Add("Resolved addresses: $($ips -join ', ')")
    } catch { $report.Add("Name resolution failed: $($_.Exception.Message)") }
    foreach ($port in @(445,135)) {
        try {
            $ok = Test-NetConnection -ComputerName $HostName -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
            $report.Add("TCP ${port}: $ok")
        } catch { $report.Add("TCP ${port}: check failed: $($_.Exception.Message)") }
    }
    try { $report.Add("Local Print Spooler: $((Get-Service spooler -ErrorAction Stop).Status)") }
    catch { $report.Add("Local spooler check failed: $($_.Exception.Message)") }
    try {
        $drivers = @(Get-PrinterDriver -ErrorAction Stop | Select-Object -ExpandProperty Name)
        $report.Add("Local drivers: $($drivers -join '; ')")
        $report.Add("Client mapping present: $([bool](Get-Printer -Name $connection -ErrorAction SilentlyContinue))")
    } catch { $report.Add("Local printer inventory failed: $($_.Exception.Message)") }
    $report | ForEach-Object { Write-Host $_ }
    Write-Host 'TCP 445 hanya tes SMB; share, login, driver dan hasil cetak belum terbukti. TCP 135 juga belum menguji port RPC dinamis.' -ForegroundColor Yellow
    Write-Host 'Login berulang/Access denied: gunakan HOST\akun yang ada di host. Driver diblokir: pasang driver resmi dengan izin admin. Host tidak ditemukan: cek DNS/IP dan routing.'
    Write-Host 'Jika SMB terbuka tetapi Connect gagal, cek spooler host, nama share, driver dan RPC/firewall host. Jangan aktifkan SMB1 atau matikan firewall/Point and Print.'
    $reportPath = Join-Path ([IO.Path]::GetTempPath()) "PrinterDiagnostic-$([guid]::NewGuid().ToString('N')).txt"
    try { $report | Set-Content -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop; Write-Host "[REPORT] $reportPath" }
    catch { Write-Host "[WARN] Laporan tidak tersimpan: $_" -ForegroundColor Yellow }
    while ($true) {
        Write-Host "`n[1] Buka host untuk login  [2] Buka Credential Manager  [3] Start spooler lokal jika berhenti"
        Write-Host '[4] Cek daftar share printer di host  [5] Buka pengelolaan driver lokal  [6] Coba Connect lagi  [0] Kembali'
        $action = Read-Host 'Pilih tindakan (tidak ada perbaikan otomatis tanpa pilihan Anda)'
        try {
            switch ($action) {
                '0' { return }
                '1' { Start-Process explorer.exe -ArgumentList "`"\\$HostName`"" -ErrorAction Stop; Write-Host 'Login memakai akun host. Setelah berhasil, pilih [6].' }
                '2' { Start-Process control.exe -ArgumentList '/name Microsoft.CredentialManager' -ErrorAction Stop; Write-Host 'Periksa hanya entri host/IP tujuan yang salah; jangan hapus seluruh kredensial atau sesi SMB.' }
                '3' {
                    $svc = Get-Service spooler -ErrorAction Stop
                    if ($svc.Status -eq 'Running') { Write-Host '[INFO] Spooler lokal sudah berjalan.' }
                    elseif ((Read-Host 'Start spooler lokal? Tidak menghapus antrean. Ketik YES') -ceq 'YES') {
                        Start-Service spooler -ErrorAction Stop
                        $svc.WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
                        Write-Host '[OK] Spooler lokal berjalan. Spooler host tetap perlu dicek di host.' -ForegroundColor Green
                    }
                }
                '4' {
                    Write-Host 'Memeriksa host lewat RPC; butuh akses yang sesuai. Gagal membaca daftar bukan bukti share tidak ada.'
                    $shares = @(Get-Printer -ComputerName $HostName -ErrorAction Stop | Where-Object { $_.Shared })
                    $shares | Format-Table Name,ShareName,DriverName -AutoSize | Out-String | Write-Host
                    if (@($shares | Where-Object { $_.ShareName -eq $ShareName }).Count -eq 0) { Write-Host '[WARN] Share tidak ada di hasil daftar ini. Periksa namanya di host.' -ForegroundColor Yellow }
                }
                '5' { Start-Process rundll32.exe -ArgumentList 'printui.dll,PrintUIEntry /s /t2' -ErrorAction Stop; Write-Host 'Gunakan driver resmi sesuai model dan arsitektur Windows; pemasangan mungkin perlu admin.' }
                '6' {
                    if (Get-Printer -Name $connection -ErrorAction SilentlyContinue) {
                        Write-Host '[INFO] Mapping sudah ada. Uji Test Page; jangan menghapusnya otomatis.'; return
                    }
                    Add-Printer -ConnectionName $connection -ErrorAction Stop
                    if (-not (Get-Printer -Name $connection -ErrorAction SilentlyContinue)) { throw 'Mapping belum terverifikasi setelah Add-Printer.' }
                    Write-Host "[OK] Terhubung: $connection. Lanjutkan Print Test Page dan tes dari aplikasi kerja." -ForegroundColor Green
                    return
                }
                default { Write-Host '[WARN] Pilihan tidak valid.' }
            }
        } catch {
            $details = "Action $action failed: $($_.Exception.Message); HRESULT: $('0x{0:X8}' -f ($_.Exception.HResult -band 0xFFFFFFFFL)); ID: $($_.FullyQualifiedErrorId)"
            Write-Host "[ERROR] $details" -ForegroundColor Red
            try { Add-Content -LiteralPath $reportPath -Value $details -Encoding UTF8 -ErrorAction Stop } catch {}
        }
    }
}

function Add-ToolkitSharedPrinterClient {
    $hostInput = Read-Host "Enter printer host name or IP address (e.g. 192.168.10.160)"
    $hostName = $hostInput.Trim().TrimStart('\\').TrimEnd('\\')
    $shareName = (Read-Host 'Enter printer share name (without \\)').Trim()

    if ([string]::IsNullOrWhiteSpace($hostName) -or $hostName -match '[\\/]' -or
        -not (Test-ToolkitPrinterShareName -ShareName $shareName)) {
        Write-Host '[ERROR] Invalid host or share name.' -ForegroundColor Red
        return
    }

    $connectionName = "\\$hostName\$shareName"
    try {
        Write-Host "Testing SMB connectivity to $hostName (TCP 445)..." -ForegroundColor Gray
        $reachable = Test-NetConnection -ComputerName $hostName -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $reachable) {
            Write-Host "[ERROR] $hostName is not reachable on TCP 445. Check routing, firewall, and that the host is online." -ForegroundColor Red
            if ((Read-Host 'Jalankan diagnosis koneksi? (Y/N)') -match '^[Yy]$') { Invoke-ToolkitPrinterConnectionDiagnostic -HostName $hostName -ShareName $shareName }
            return
        }

        if (Get-Printer -Name $connectionName -ErrorAction SilentlyContinue) {
            Write-Host "[INFO] Client mapping already exists: $connectionName" -ForegroundColor Yellow
            return
        }

        Add-Printer -ConnectionName $connectionName -ErrorAction Stop
        if (Get-Printer -Name $connectionName -ErrorAction SilentlyContinue) {
            Write-Host "[OK] Shared printer connected: $connectionName" -ForegroundColor Green
        } else {
            Write-Host '[WARN] Windows accepted the request, but the printer mapping was not found during verification.' -ForegroundColor Yellow
            if ((Read-Host 'Jalankan diagnosis koneksi? (Y/N)') -match '^[Yy]$') { Invoke-ToolkitPrinterConnectionDiagnostic -HostName $hostName -ShareName $shareName }
        }
    } catch {
        Write-Host "[ERROR] Could not connect to ${connectionName}: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '       If Windows blocks the driver, install the signed driver locally and retry.' -ForegroundColor Gray
        $connectError = $_
        if ((Read-Host 'Jalankan diagnosis dan opsi perbaikan? (Y/N)') -match '^[Yy]$') {
            Invoke-ToolkitPrinterConnectionDiagnostic -HostName $hostName -ShareName $shareName -ConnectionError $connectError
        }
    }
}

function Test-ToolkitPrinterShareConnection {
    $hostInput = Read-Host "Enter printer host name or IP address"
    $hostName = $hostInput.Trim().TrimStart('\\').TrimEnd('\\')
    $shareName = (Read-Host 'Enter printer share name (without \\)').Trim()
    if ([string]::IsNullOrWhiteSpace($hostName) -or $hostName -match '[\\/]' -or
        -not (Test-ToolkitPrinterShareName -ShareName $shareName)) {
        Write-Host '[ERROR] Invalid host or share name.' -ForegroundColor Red
        return
    }

    $connectionName = "\\$hostName\$shareName"
    $portCheck = Test-NetConnection -ComputerName $hostName -Port 445 -WarningAction SilentlyContinue
    $mapped = Get-Printer -Name $connectionName -ErrorAction SilentlyContinue
    Write-Host "`nPrinter share test: $connectionName" -ForegroundColor Cyan
    Write-Host "   TCP 445 reachable : $($portCheck.TcpTestSucceeded)" -ForegroundColor (if ($portCheck.TcpTestSucceeded) { 'Green' } else { 'Red' })
    Write-Host "   Mapped on this PC  : $([bool]$mapped)" -ForegroundColor (if ($mapped) { 'Green' } else { 'Yellow' })
    if (-not $portCheck.TcpTestSucceeded) {
        Write-Host '   Check the host spooler, Windows firewall, routing, and SMB access.' -ForegroundColor Yellow
    }
}

function Remove-ToolkitPrinterShareMapping {
    $localPrinters = @(Get-Printer -ErrorAction SilentlyContinue)
    Write-Host "`n[1] Unshare a local host printer" -ForegroundColor Yellow
    Write-Host '[2] Remove a client printer mapping' -ForegroundColor Yellow
    $removeChoice = Read-Host 'Select action (1-2)'

    if ($removeChoice -eq '1') {
        $shared = @($localPrinters | Where-Object { $_.Shared })
        if ($shared.Count -eq 0) { Write-Host '[INFO] No shared local printers found.' -ForegroundColor Gray; return }
        for ($i = 0; $i -lt $shared.Count; $i++) { Write-Host ("   [{0}] {1} (Share: {2})" -f ($i + 1), $shared[$i].Name, $shared[$i].ShareName) }
        $selectionText = Read-Host "Printer number (1-$($shared.Count))"
        try { $selection = [int]$selectionText - 1 } catch { $selection = -1 }
        if ($selection -lt 0 -or $selection -ge $shared.Count) { Write-Host '[ERROR] Invalid selection.' -ForegroundColor Red; return }
        $selected = $shared[$selection]
        if ((Read-Host "Type YES to unshare '$($selected.Name)'") -cne 'YES') { Write-Host '[CANCELLED]' -ForegroundColor Yellow; return }
        try { Set-Printer -Name $selected.Name -Shared $false -ErrorAction Stop; Write-Host "[OK] Printer '$($selected.Name)' is no longer shared." -ForegroundColor Green }
        catch { Write-Host "[ERROR] Could not unshare printer: $($_.Exception.Message)" -ForegroundColor Red }
    } elseif ($removeChoice -eq '2') {
        $mapped = @($localPrinters | Where-Object { $_.Name -like '\\*' })
        if ($mapped.Count -eq 0) { Write-Host '[INFO] No shared-printer client mappings found.' -ForegroundColor Gray; return }
        for ($i = 0; $i -lt $mapped.Count; $i++) { Write-Host ("   [{0}] {1}" -f ($i + 1), $mapped[$i].Name) }
        $selectionText = Read-Host "Mapping number (1-$($mapped.Count))"
        try { $selection = [int]$selectionText - 1 } catch { $selection = -1 }
        if ($selection -lt 0 -or $selection -ge $mapped.Count) { Write-Host '[ERROR] Invalid selection.' -ForegroundColor Red; return }
        $selected = $mapped[$selection]
        if ((Read-Host "Type YES to remove '$($selected.Name)'") -cne 'YES') { Write-Host '[CANCELLED]' -ForegroundColor Yellow; return }
        try { Remove-Printer -Name $selected.Name -ErrorAction Stop; Write-Host "[OK] Client mapping removed: $($selected.Name)" -ForegroundColor Green }
        catch { Write-Host "[ERROR] Could not remove client mapping: $($_.Exception.Message)" -ForegroundColor Red }
    } else {
        Write-Host '[ERROR] Invalid selection.' -ForegroundColor Red
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
    Write-Host "   [13] MeshAgent Setup              (Local installer, service verification)"
    Write-Host ""
    Write-Host "   [0] Exit" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "Select option (0-13)"

    switch ($choice) {
        "13" {
            Write-Host 'Use the Windows agent downloaded from DOK Office PCs at https://192.168.10.160:4443/.' -ForegroundColor Cyan
            Write-Host 'This enables persistent remote management. No firewall or admin-account changes are made here.' -ForegroundColor Yellow
            $meshInstaller = Read-Host 'Full path to the group-specific installer for this CPU architecture'
            if ((Test-Path -LiteralPath $meshInstaller -PathType Leaf) -and ((Read-Host 'Install this trusted agent? Type YES') -ceq 'YES')) {
                $meshInstalled = Install-ToolkitAgent -Installer $meshInstaller -Arguments '-fullinstall' -ServiceName 'Mesh Agent'
                if ($meshInstalled) { Write-Host 'Verify this PC is Online in the DOK Office PCs dashboard.' -ForegroundColor Yellow }
            } else { Write-Host '[SKIPPED] Installer missing or installation not confirmed.' -ForegroundColor Yellow }
            Read-Host 'Press Enter to return' | Out-Null
        }
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

                $failedApps = @()
                $rebootRequired = $false
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
                            if ($proc.ExitCode -notin @(0, 3010)) { throw "Installer exit code $($proc.ExitCode). Source installer retained." }
                            if ($proc.ExitCode -eq 3010) { $rebootRequired = $true }
                            Write-Host "   [OK] $($app.name) installer completed (code $($proc.ExitCode))." -ForegroundColor Green
                            $installed = $true
                        } catch {
                            Write-Host "   [WARN] Offline execution failed: $_" -ForegroundColor Yellow
                        }
                    }

                    # 2. Fallback to Winget if offline installer not found
                    if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
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
                                if ($proc.ExitCode -notin @(0, 3010)) { throw "Installer exit code $($proc.ExitCode). Installer retained at $($app.out)." }
                                if ($proc.ExitCode -eq 3010) { $rebootRequired = $true }
                                Remove-Item $app.out -Force -ErrorAction SilentlyContinue
                                $installed = $true
                                Write-Host "   [OK] $($app.name) installer completed (code $($proc.ExitCode))." -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "   [WARN] Direct download failed for $($app.name): $_" -ForegroundColor Red
                        }
                    }
                    if (-not $installed) { $failedApps += $app.name }
                }

                if ($failedApps.Count) {
                    Write-Host "`n[ERROR] Installation not confirmed: $($failedApps -join ', ')" -ForegroundColor Red
                } else {
                    Write-Host "`n[OK] All selected installers reported success. Verify applications before handover." -ForegroundColor Green
                }
                if ($rebootRequired) { Write-Host '[REBOOT REQUIRED] Restart Windows to finish installation.' -ForegroundColor Yellow }
                Start-Sleep -Seconds 2
            }
        }
        "2" {
            Show-ToolkitPerformanceMenu
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
                Write-Host "   [6] Share Local Printer (Host)                 (Create a protected Windows printer share)" -ForegroundColor Cyan
                Write-Host "   [7] Connect Shared Printer (Client)            (Add \\HOST\SHARE and test SMB)" -ForegroundColor Cyan
                Write-Host "   [8] Printer Share Status / Report              (List shares, TCP 445 test, save report)" -ForegroundColor Cyan
                Write-Host "   [9] Remove Printer Share / Client Mapping     (Rollback a share or connection)" -ForegroundColor Yellow
                Write-Host "   [10] Diagnose / Repair Printer Sharing Connection (Login, SMB/RPC, driver, retry)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "   [0] Back to Main Menu" -ForegroundColor Red
                Write-Host "=========================================================================" -ForegroundColor Cyan
                Write-Host ""

                $printChoice = Read-Host "Select option (0-10)"
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
                    "6" {
                        Write-Host "`n=== Share a Local Printer (Host Mode) ===" -ForegroundColor Yellow
                        $hostPrinters = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '\\*' })
                        if ($hostPrinters.Count -eq 0) {
                            Write-Host '[ERROR] No local printers were found.' -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }
                        for ($i = 0; $i -lt $hostPrinters.Count; $i++) {
                            $shareText = if ($hostPrinters[$i].Shared) { "Shared as $($hostPrinters[$i].ShareName)" } else { 'Not shared' }
                            Write-Host ("   [{0}] {1} ({2}, Driver: {3})" -f ($i + 1), $hostPrinters[$i].Name, $shareText, $hostPrinters[$i].DriverName)
                        }
                        $pIndexText = Read-Host "Printer number (1-$($hostPrinters.Count))"
                        try { $pIdx = [int]$pIndexText - 1 } catch { $pIdx = -1 }
                        if ($pIdx -lt 0 -or $pIdx -ge $hostPrinters.Count) {
                            Write-Host '[ERROR] Invalid printer selection.' -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }

                        $selectedPrinter = $hostPrinters[$pIdx]
                        $defaultShare = Get-ToolkitDefaultPrinterShareName -PrinterName $selectedPrinter.Name
                        $shareName = (Read-Host "Share name (default: $defaultShare)").Trim()
                        if ([string]::IsNullOrWhiteSpace($shareName)) { $shareName = $defaultShare }
                        if ((Read-Host "Type YES to share '$($selectedPrinter.Name)' as '$shareName'") -cne 'YES') {
                            Write-Host '[CANCELLED] No changes were made.' -ForegroundColor Yellow
                        } else {
                            Set-ToolkitPrinterShare -PrinterName $selectedPrinter.Name -ShareName $shareName | Out-Null
                        }
                        Start-Sleep -Seconds 2
                    }
                    "7" {
                        Write-Host "`n=== Connect to a Shared Printer (Client Mode) ===" -ForegroundColor Yellow
                        Add-ToolkitSharedPrinterClient
                        Start-Sleep -Seconds 2
                    }
                    "8" {
                        Write-Host "`n=== Printer Share Status & Report ===" -ForegroundColor Yellow
                        $inventory = @(Get-ToolkitPrinterInventory)
                        if ($inventory.Count -eq 0) {
                            Write-Host '[INFO] No printers are installed on this PC.' -ForegroundColor Gray
                        } else {
                            $inventory | Format-Table Name, Shared, ShareName, Driver, Port, Status -AutoSize | Out-String | Write-Host -ForegroundColor White
                        }

                        $desktopPath = [Environment]::GetFolderPath('Desktop')
                        $reportPath = Join-Path $desktopPath "PRINTER_SHARE_REPORT_$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
                        $ipv4 = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                            Select-Object -ExpandProperty IPAddress)
                        $spoolerStatus = (Get-Service -Name spooler -ErrorAction SilentlyContinue).Status
                        @(
                            'IT Support Toolkit - Printer Share Report'
                            "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
                            "Computer: $env:COMPUTERNAME"
                            "IPv4: $($ipv4 -join ', ')"
                            "Spooler: $spoolerStatus"
                            ''
                            'Printers:'
                            ($inventory | Format-Table Name, Shared, ShareName, Driver, Port, Status -AutoSize | Out-String)
                        ) | Set-Content -LiteralPath $reportPath -Encoding UTF8
                        Write-Host "[OK] Report saved to $reportPath" -ForegroundColor Green

                        $testNow = (Read-Host 'Test a remote printer host now? (Y/N)').Trim().ToUpperInvariant()
                        if ($testNow -eq 'Y') { Test-ToolkitPrinterShareConnection }
                        Start-Sleep -Seconds 2
                    }
                    "9" {
                        Write-Host "`n=== Remove Printer Share / Client Mapping ===" -ForegroundColor Yellow
                        Remove-ToolkitPrinterShareMapping
                        Start-Sleep -Seconds 2
                    }
                    "10" {
                        Invoke-ToolkitPrinterConnectionDiagnostic
                        Read-Host 'Press Enter to return' | Out-Null
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
                Set-ToolkitDeviceIdentity -Identity $inputIdentity | Out-Null
            }

            # 1. Create or update local admin account for remote deployment
            $deployUser = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LOCAL_ADMIN_USER')
            if ([string]::IsNullOrWhiteSpace($deployUser)) { $deployUser = 'AsetDP' }
            $localAdminPasswordText = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LOCAL_ADMIN_PASSWORD')
            if ([string]::IsNullOrWhiteSpace($localAdminPasswordText)) {
                $localAdminPasswordText = '@AsetDP25'
            }
            $deployPass = ConvertTo-SecureString $localAdminPasswordText -AsPlainText -Force
            $adminReady = Set-ToolkitClientAdministrator -UserName $deployUser -Password $deployPass

            Set-ToolkitLocalAccountDisplayName | Out-Null

            # 2. Enable Firewall Rules, Services & Remote UAC (LocalAccountTokenFilterPolicy)
            $remoteReady = Enable-ToolkitRemoteInventoryAccess
            if (-not $adminReady -or -not $remoteReady) {
                Write-Host '      [WARN] Remote deployment prerequisites are incomplete. LsAgent setup can still continue.' -ForegroundColor Yellow
            }
            $existingLsAgent = Get-ToolkitLsAgentService
            if ($existingLsAgent) {
                Write-Host "`n[INFO] Existing LsAgent detected: $($existingLsAgent.DisplayName)" -ForegroundColor Cyan
                Repair-ToolkitLsAgentService | Out-Null
                Write-Host '      Verify the next agent check-in and remote scanning credentials in Lansweeper.' -ForegroundColor Gray
                Read-Host 'Press Enter to return to Main Menu' | Out-Null
                continue
            }

            # 2. Install LsAgent using the same source selection and local staging
            # pattern as Kaspersky: USB -> local disk -> network share by default.
            $agentFileName = 'LsAgent-windows.exe'
            $usbLsAgent = Find-ToolkitUsbInstaller -FileName $agentFileName
            $localLsAgent = $null
            foreach ($localFolder in @('D:\Sharing\Software', 'C:\Program Files (x86)\Lansweeper\Client')) {
                $localCandidate = Join-Path $localFolder $agentFileName
                if (Test-Path -LiteralPath $localCandidate -PathType Leaf) { $localLsAgent = $localCandidate; break }
            }

            Write-Host "`nSelect LsAgent Installer Source:" -ForegroundColor Cyan
            Write-Host '   [1] Auto-Detect (Flash Drive -> Local Disk -> Network Share)'
            Write-Host '   [2] Flash Drive (USB)'
            Write-Host '   [3] Local Disk (D:\Sharing\Software)'
            Write-Host '   [4] Network Share (\\192.168.10.160\Sharing)'
            Write-Host '   [0] Skip LsAgent installation' -ForegroundColor Red
            $agentSourceChoice = Read-Host 'Select source (0-4) [Default: 1]'
            if ([string]::IsNullOrWhiteSpace($agentSourceChoice)) { $agentSourceChoice = '1' }
            if ($agentSourceChoice -notin @('0', '1', '2', '3', '4')) {
                Write-Host '[WARN] Invalid source choice; using Auto-Detect.' -ForegroundColor Yellow
                $agentSourceChoice = '1'
            }

            # Direct-LAN mode does not require a Cloud Relay key. If an optional
            # relay key is supplied through the environment, add it as fallback.
            $agentArgs = '--mode unattended --server 192.168.10.160 --port 9524'
            $agentKey = [Environment]::GetEnvironmentVariable('IT_TOOLKIT_LSAGENT_KEY')
            if (-not [string]::IsNullOrWhiteSpace($agentKey)) {
                $agentArgs += " --agentkey $agentKey"
                Write-Host '      [INFO] Cloud Relay fallback enabled from IT_TOOLKIT_LSAGENT_KEY.' -ForegroundColor Gray
            }

            $lsAgentInstaller = $null
            $lsAgentSource = $null
            if ($agentSourceChoice -eq '0') {
                Write-Host '[SKIPPED] LsAgent installation skipped by request.' -ForegroundColor Yellow
            } elseif ($agentSourceChoice -eq '2') {
                if ($usbLsAgent) { $lsAgentInstaller = $usbLsAgent; $lsAgentSource = 'Flash Drive' }
            } elseif ($agentSourceChoice -eq '3') {
                if ($localLsAgent) { $lsAgentInstaller = $localLsAgent; $lsAgentSource = 'Local Disk' }
            } elseif ($agentSourceChoice -eq '4') {
                if (Connect-ToolkitDeploymentShare -Name 'ToolkitShare' -Root '\\192.168.10.160\Sharing') {
                    $networkCandidate = 'ToolkitShare:\Software\LsAgent-windows.exe'
                    if (Test-Path -LiteralPath $networkCandidate -PathType Leaf) {
                        $lsAgentInstaller = $networkCandidate
                        $lsAgentSource = 'Network Share'
                    }
                }
                if (-not $lsAgentInstaller -and (Connect-ToolkitDeploymentShare -Name 'ToolkitPackage' -Root '\\192.168.10.160\DefaultPackageShare$')) {
                    $networkCandidate = 'ToolkitPackage:\Installers\LsAgent-windows.exe'
                    if (Test-Path -LiteralPath $networkCandidate -PathType Leaf) {
                        $lsAgentInstaller = $networkCandidate
                        $lsAgentSource = 'Lansweeper Package Share'
                    }
                }
            } else {
                if ($usbLsAgent) { $lsAgentInstaller = $usbLsAgent; $lsAgentSource = 'Flash Drive' }
                elseif ($localLsAgent) { $lsAgentInstaller = $localLsAgent; $lsAgentSource = 'Local Disk' }
                else {
                    if (Connect-ToolkitDeploymentShare -Name 'ToolkitShare' -Root '\\192.168.10.160\Sharing') {
                        $networkCandidate = 'ToolkitShare:\Software\LsAgent-windows.exe'
                        if (Test-Path -LiteralPath $networkCandidate -PathType Leaf) {
                            $lsAgentInstaller = $networkCandidate
                            $lsAgentSource = 'Network Share'
                        }
                    }
                    if (-not $lsAgentInstaller -and (Connect-ToolkitDeploymentShare -Name 'ToolkitPackage' -Root '\\192.168.10.160\DefaultPackageShare$')) {
                        $networkCandidate = 'ToolkitPackage:\Installers\LsAgent-windows.exe'
                        if (Test-Path -LiteralPath $networkCandidate -PathType Leaf) {
                            $lsAgentInstaller = $networkCandidate
                            $lsAgentSource = 'Lansweeper Package Share'
                        }
                    }
                }
            }

            if ($agentSourceChoice -ne '0') {
                if ($lsAgentInstaller) {
                    $lsVerified = Install-ToolkitAgent -Installer $lsAgentInstaller -Arguments $agentArgs -ServiceName 'LansweeperAgentService' -SourceLabel $lsAgentSource
                    if ($lsVerified) {
                        Write-Host '      [NEXT] Check for this asset in Lansweeper after the next agent scan; successful service start does not prove server check-in.' -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "      [ERROR] LsAgent installer was not found for source choice $agentSourceChoice." -ForegroundColor Red
                    Write-Host '      No installer was executed; the onboarding network settings above remain applied.' -ForegroundColor Yellow
                }
            }
            Remove-PSDrive -Name 'ToolkitShare', 'ToolkitPackage' -Force -ErrorAction SilentlyContinue

            Write-Host "`n[INFO] Onboarding steps finished. Review errors above; verify the latest check-in on the Lansweeper server." -ForegroundColor Yellow
            Write-Host "`nPress Enter to return to Main Menu..." -ForegroundColor Yellow
            Read-Host | Out-Null
        }
        "8" {
            Write-Host "`nInstalling Kaspersky Endpoint Security 14.0..." -ForegroundColor Yellow
            
            # 0. Single Prompt for Device Identity / Hostname (e.g. BERSA-DOK-HRGA or RIADTHON-DOK-REPAIRMAINTENANCE)
            $inputIdentity = Read-Host "Enter Device Hostname (e.g. BERSA-DOK-HRGA) [Press Enter to skip]"

            if ($inputIdentity) {
                Set-ToolkitDeviceIdentity -Identity $inputIdentity | Out-Null
            }

            Set-ToolkitLocalAccountDisplayName | Out-Null

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

            # Search the script's USB drive first, then other removable drives.
            # The toolkit layout is USB:\software\Install.ps1 + USB:\software\Software\installer.exe.
            $installerName = 'Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe'
            $fdInstaller = $null
            $usbDrives = @(Get-PSDrive -PSProvider FileSystem | Where-Object {
                try { [System.IO.DriveInfo]::new($_.Root).DriveType -eq [System.IO.DriveType]::Removable }
                catch { $false }
            })
            if ($PSScriptRoot) {
                $usbDrives = @($usbDrives | Sort-Object @{ Expression = { if ($PSScriptRoot.StartsWith($_.Root, [System.StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 } } }, Name)
            }
            foreach ($drive in $usbDrives) {
                foreach ($folder in @('software\Software', 'Software', 'software\soft', 'soft', 'software', '')) {
                    $candidate = Join-Path (Join-Path $drive.Root $folder) $installerName
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $fdInstaller = $candidate; break }
                }
                if ($fdInstaller) { break }
            }

            $networkSourceNeeded = $sourceChoice -eq '4' -or
                ($sourceChoice -eq '1' -and -not $fdInstaller -and -not (Test-Path $localInstaller))
            if ($networkSourceNeeded -and (Connect-ToolkitDeploymentShare -Name 'ToolkitShare' -Root '\\192.168.10.160\Sharing')) {
                $uncInstaller = 'ToolkitShare:\Software\Kaspersky Endpoint Security for Windows 14.0.0 (14.0.0.504).exe'
            }

            $sourceInstaller = $null
            $sourceLabel = $null
            switch ($sourceChoice) {
                '2' { $sourceInstaller = $fdInstaller; $sourceLabel = 'USB' }
                '3' { if (Test-Path -LiteralPath $localInstaller -PathType Leaf) { $sourceInstaller = $localInstaller }; $sourceLabel = 'Local Disk' }
                '4' { if ($uncInstaller -and (Test-Path -LiteralPath $uncInstaller -PathType Leaf)) { $sourceInstaller = $uncInstaller }; $sourceLabel = 'Network Share' }
                default {
                    if ($fdInstaller) { $sourceInstaller = $fdInstaller; $sourceLabel = 'USB' }
                    elseif (Test-Path -LiteralPath $localInstaller -PathType Leaf) { $sourceInstaller = $localInstaller; $sourceLabel = 'Local Disk' }
                    elseif ($uncInstaller -and (Test-Path -LiteralPath $uncInstaller -PathType Leaf)) { $sourceInstaller = $uncInstaller; $sourceLabel = 'Network Share' }
                }
            }

            $tempInstaller = Join-Path "$env:SystemDrive\Temp" "KES14_Setup_$PID.exe"
            $partialInstaller = "$tempInstaller.partial"
            $targetInstallerToRun = $null
            $installSucceeded = $false
            if ($sourceInstaller) {
                try {
                    New-Item -Path (Split-Path $tempInstaller -Parent) -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    $sourceFile = Get-Item -LiteralPath $sourceInstaller -ErrorAction Stop
                    Write-Host "      [$sourceLabel] Copying installer to $tempInstaller ..." -ForegroundColor Gray
                    Copy-Item -LiteralPath $sourceInstaller -Destination $partialInstaller -Force -ErrorAction Stop
                    $copiedFile = Get-Item -LiteralPath $partialInstaller -ErrorAction Stop
                    if ($copiedFile.Length -ne $sourceFile.Length -or
                        (Get-FileHash -LiteralPath $sourceInstaller -Algorithm SHA256 -ErrorAction Stop).Hash -ne
                        (Get-FileHash -LiteralPath $partialInstaller -Algorithm SHA256 -ErrorAction Stop).Hash) {
                        throw 'The copied installer does not match the source file.'
                    }
                    Move-Item -LiteralPath $partialInstaller -Destination $tempInstaller -ErrorAction Stop
                    $targetInstallerToRun = $tempInstaller
                    Write-Host '      [OK] Installer copied and verified. USB can now be ejected.' -ForegroundColor Green
                } catch {
                    Write-Host "      [ERROR] Installer copy/verification failed: $($_.Exception.Message)" -ForegroundColor Red
                    Remove-Item -LiteralPath $partialInstaller -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "      [ERROR] Kaspersky installer not found for source choice $sourceChoice." -ForegroundColor Red
            }

            if ($targetInstallerToRun) {
                try {
                    Write-Host "      [Executing] Launching Kaspersky installer from $targetInstallerToRun ..." -ForegroundColor Yellow
                    $installStartedAt = Get-Date
                    $proc = Start-Process -FilePath $targetInstallerToRun -Wait -PassThru -ErrorAction Stop
                    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                        $installSucceeded = $true
                        Write-Host "      [OK] Kaspersky installer completed (ExitCode: $($proc.ExitCode))." -ForegroundColor Green
                        if ($proc.ExitCode -eq 3010) { Write-Host '      [REBOOT REQUIRED] Installation is pending a Windows restart.' -ForegroundColor Yellow }
                        Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
                    } else {
                        Write-Host "      [ERROR] Kaspersky installer exited with code $($proc.ExitCode). Installer retained at $tempInstaller for diagnosis." -ForegroundColor Red
                        $packageLog = Join-Path $env:TEMP 'klpkinst.log'
                        if ($proc.ExitCode -eq 4 -and (Test-Path -LiteralPath $packageLog -PathType Leaf) -and
                            (Get-Item -LiteralPath $packageLog).LastWriteTime -ge $installStartedAt.AddSeconds(-5) -and
                            (Select-String -LiteralPath $packageLog -SimpleMatch 'Bad parameter "VerifyCertDate"' -Quiet)) {
                            Write-Host '      [CAUSE] The stand-alone package certificate is out of date (VerifyCertDate).' -ForegroundColor Red
                            Write-Host '      [ACTION] Regenerate and download a fresh installation package from your Kaspersky console, then replace the old EXE on USB.' -ForegroundColor Yellow
                        }
                        if (Test-Path -LiteralPath $packageLog -PathType Leaf) {
                            Write-Host "      [LOG] $packageLog" -ForegroundColor Gray
                        }
                    }
                } catch {
                    Write-Host "      [ERROR] Kaspersky installer could not start: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "      Installer retained at $tempInstaller for diagnosis." -ForegroundColor Yellow
                }
            }

            if (-not $installSucceeded) { Write-Host "`n[ERROR] Kaspersky task did not complete successfully." -ForegroundColor Red }
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
