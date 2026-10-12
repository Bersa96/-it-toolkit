$ErrorActionPreference = 'Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Parser failure' }
$functions=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Get-ToolkitPerformanceHardware','Invoke-ToolkitPerformanceProfile','Show-ToolkitPerformanceMenu')},$true)
foreach ($f in $functions) { Invoke-Expression $f.Extent.Text }
# Hardware mocks only: no real tuning, installation, registry write or volume optimization.
function Get-Partition { param($DriveLetter,$ErrorAction) [pscustomobject]@{DiskNumber=0} }
function Get-Disk { param($ErrorAction) if ($script:mode -eq 'Unavailable') { throw 'Unavailable' }; [pscustomobject]@{BusType=$(if($script:mode -eq 'NVMe'){'NVMe'}else{'SATA'});UniqueId='disk-id';SerialNumber='serial'} }
function Get-PhysicalDisk { param($ErrorAction) [pscustomobject]@{UniqueId=$(if($script:mode -eq 'Unknown'){'other'}else{'disk-id'});SerialNumber='other';MediaType=$(if($script:mode -eq 'HDD'){'HDD'}else{'SSD'})} }
function Get-CimInstance { param($ClassName,$ErrorAction) if($script:mode -eq 'Unavailable'){throw 'Unavailable'}; [pscustomobject]@{TotalPhysicalMemory=16GB} }
foreach($case in @(@('NVMe','SSD'),@('SATA','SSD'),@('HDD','HDD'),@('Unknown','Unknown'),@('Unavailable','Unknown'))) {
    $script:mode=$case[0]; $result=Get-ToolkitPerformanceHardware
    if($result.Media -ne $case[1]) { throw "Wrong media: $($case[0])" }
    if($script:mode -eq 'Unavailable' -and $null -ne $result.RAMGB){throw 'Unknown RAM must remain null'}
    Write-Output "PASS hardware: $($case[0]) -> $($result.Media)"
}
# Exercise cancelled profile: mocked read operations only, guard all writes with failures.
function Test-Path { param($LiteralPath) $false }
function Read-Host { param($Prompt) 'NO' }
function New-Item { throw 'Unexpected mutation' }
function New-ItemProperty { throw 'Unexpected mutation' }
function Export-Clixml { throw 'Unexpected mutation' }
$script:mode='NVMe'
Invoke-ToolkitPerformanceProfile 'Smart'
Write-Output 'PASS cancelled profile: no mutation'
$text=$functions.Extent.Text -join "`n"
foreach($forbidden in @('Stop-Service','Set-Service','Stop-Process','Remove-AppxProvisionedPackage','-AllUsers','BootOptimizeFunction','DisableDeleteNotify','EnablePrefetcher')) {
    if($text.Contains($forbidden)){throw "Unsafe command remains: $forbidden"}
}
Write-Output 'PASS conservative profile regression checks'
