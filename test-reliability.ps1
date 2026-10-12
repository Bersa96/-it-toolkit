$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.ServiceProcess
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Get-ToolkitPeArchitecture','Get-ToolkitMeshSettings','Test-ToolkitMeshRuntime','Convert-ToolkitSmbShare','Get-ToolkitOtherAntivirus','Test-ToolkitAntivirusReady','Get-ToolkitRdpWrapperDll','Invoke-ToolkitRdpWrapper','Install-ToolkitAgent')) {
    $f=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $f){throw "Missing $name"}; Invoke-Expression $f.Extent.Text
}
function Assert($Condition,$Message) { if(-not $Condition){throw $Message} }
# Only synthetic files in a unique test directory; no real service/registry/firewall writes.
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('ToolkitReliabilityTest-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$exe=Join-Path $testDir 'agent.exe'
$bytes=New-Object byte[] 128
$bytes[0]=0x4d;$bytes[1]=0x5a;$bytes[60]=64;$bytes[64]=0x50;$bytes[65]=0x45;$bytes[68]=0x64;$bytes[69]=0x86
[IO.File]::WriteAllBytes($exe,$bytes)
Assert ((Get-ToolkitPeArchitecture $exe) -eq 'AMD64') 'PE AMD64 detection failed'
$bytes[60]=255;[IO.File]::WriteAllBytes($exe,$bytes)
$rejected=$false;try{Get-ToolkitPeArchitecture $exe | Out-Null}catch{$rejected=$true}
Assert $rejected 'Malformed PE accepted'
$bytes[60]=64
$policy="MeshID=group1`nServerID=server1`nMeshServer=wss://example.test:4443/agent.ashx`n"
$payload=[Text.Encoding]::UTF8.GetBytes($policy)
$length=[BitConverter]::GetBytes([uint32]$payload.Length);[Array]::Reverse($length)
$marker=[byte[]](0xb9,0x96,0x01,0x58,0x80,0x54,0x4a,0x19,0xb7,0xf7,0xe9,0xbe,0x44,0x91,0x4c,0x19)
[IO.File]::WriteAllBytes($exe,([byte[]]($bytes+$payload+$length+$marker)))
$expected=Get-ToolkitMeshSettings $exe
Assert ($expected.MeshID -eq 'group1') 'Embedded Mesh policy parsing failed'
$msh=[IO.Path]::ChangeExtension($exe,'.msh');[IO.File]::WriteAllText($msh,$policy)
Assert ((Get-ToolkitMeshSettings $msh).MeshServer -eq $expected.MeshServer) 'Sidecar parsing failed'
[IO.File]::WriteAllText($msh,'MeshID=only')
$rejected=$false;try{Get-ToolkitMeshSettings $msh | Out-Null}catch{$rejected=$true}
Assert $rejected 'Incomplete Mesh policy accepted'
[IO.File]::WriteAllText($msh,$policy)
Write-Output 'PASS PE validation and embedded/sidecar Mesh policy validation'
function Get-CimInstance {
    param($ClassName,$Filter,$Namespace,$ErrorAction)
    if($ClassName -eq 'Win32_Service'){return [pscustomobject]@{State='Running';ProcessId=123;StartMode='Manual'}}
    if($ClassName -eq 'Win32_Process'){return [pscustomobject]@{ExecutablePath=$exe}}
    throw 'Unexpected CIM call'
}
Test-ToolkitMeshRuntime -ServiceName 'Mesh Agent' -Expected $expected -Stage (Join-Path $testDir 'stage')
$bad=@{MeshID='wrong';ServerID='server1';MeshServer=$expected.MeshServer}
$rejected=$false;try{Test-ToolkitMeshRuntime -ServiceName 'Mesh Agent' -Expected $bad -Stage (Join-Path $testDir 'stage')}catch{$rejected=$true}
Assert $rejected 'Wrong Mesh group accepted'
$rejected=$false;try{Test-ToolkitMeshRuntime -ServiceName 'Mesh Agent' -Expected $expected -Stage $testDir}catch{$rejected=$true}
Assert $rejected 'Running agent in temporary staging accepted'
Write-Output 'PASS Mesh runtime group mismatch and temporary-path rejection'
$script:old=[pscustomobject]@{Name='Office';Path='D:\Data';Description='Original';Special=$false;ScopeName='*';SecurityDescriptor='D:(A;;GR;;;AU)';CachingMode='Manual';FolderEnumerationMode='AccessBased';EncryptData=$true;ConcurrentUserLimit=12;ContinuouslyAvailable=$false}
$script:new=$null;$script:removed=@();$script:failCreate=$false;$script:badAcl=$false;$script:failDelete=$false
function Get-SmbShare { param($Name,$ErrorAction) if($Name -eq 'Office'){return $script:old};return $script:new }
function New-SmbShare {
    param($Name,$Path,$Description,$SecurityDescriptor,$CachingMode,$FolderEnumerationMode,$EncryptData,$ConcurrentUserLimit,$ContinuouslyAvailable,$ErrorAction)
    if($script:failCreate){throw 'Mock creation failure'}
    $script:new=[pscustomobject]@{Name=$Name;Path=$Path;Description=$Description;SecurityDescriptor=$SecurityDescriptor;CachingMode=$CachingMode;FolderEnumerationMode=$FolderEnumerationMode;EncryptData=$EncryptData;ConcurrentUserLimit=$ConcurrentUserLimit;ContinuouslyAvailable=$ContinuouslyAvailable}
    if($script:badAcl){$script:new.SecurityDescriptor='D:(A;;GA;;;WD)'}
}
function Remove-SmbShare { param($Name,[switch]$Force,$ErrorAction) if($Name -eq 'Office' -and $script:failDelete){throw 'Mock old share removal failed'}; $script:removed+=$Name; if($Name -eq 'Office'){$script:old=$null}else{$script:new=$null} }
$original=$script:old
Assert (Convert-ToolkitSmbShare -Name Office -NewName 'Office$') 'Share conversion failed'
Assert ($script:new.SecurityDescriptor -eq $original.SecurityDescriptor -and $script:removed -contains 'Office') 'Share ACL not retained'
foreach($case in @('create','acl','delete')) {
    $script:old=$original;$script:new=$null;$script:removed=@()
    $script:failCreate=$case -eq 'create';$script:badAcl=$case -eq 'acl';$script:failDelete=$case -eq 'delete'
    Assert (-not (Convert-ToolkitSmbShare -Name Office -NewName 'Office$')) "Failure reported as success: $case"
    Assert ($null -ne $script:old -and $null -eq $script:new -and $script:removed -notcontains 'Office') "Original share lost: $case"
}
Write-Output 'PASS SMB ACL preservation and create/verification/delete failure recovery'
function Get-ToolkitOtherAntivirus { if($script:inventoryError){throw 'Mock inventory failure'}; if($script:conflict){'Other AV'} }
function Read-Host { param($Prompt) '0' }
function Test-Path { param($LiteralPath,$PathType) if($LiteralPath -like '*RebootPending') {return $script:pending}; return $false }
function Get-ItemProperty { param($LiteralPath,$Name,$ErrorAction) $null }
function Start-Process { throw 'Unexpected real installer/GUI launch' }
$script:conflict=$true;$script:pending=$false;$script:inventoryError=$false
Assert (-not (Test-ToolkitAntivirusReady)) 'AV conflict was not deferred'
$script:conflict=$false;$script:pending=$true
Assert (-not (Test-ToolkitAntivirusReady)) 'Pending restart was ignored'
$script:pending=$false;$script:inventoryError=$true
Assert (-not (Test-ToolkitAntivirusReady)) 'Failed AV inventory was ignored'
$script:inventoryError=$false
Assert (Test-ToolkitAntivirusReady) 'Clean prerequisites were blocked'
Write-Output 'PASS antivirus conflict, pending reboot, unknown inventory and clean prerequisite gates'
# Mock RDP state and writes. Block network downloads to check the no-change failure path.
function New-Item { param($ItemType,$Path,[switch]$Force,$ErrorAction) }
function Get-Service { param($Name,$ErrorAction) [pscustomobject]@{Status='Running'} }
function Get-Item { param($LiteralPath,$ErrorAction) $k=New-Object psobject; $k | Add-Member ScriptMethod GetValueNames { @() };return $k }
function Copy-Item { throw 'Unexpected copy on failed download' }
function Export-Clixml { param($LiteralPath,[Parameter(ValueFromPipeline)]$InputObject) }
function Invoke-WebRequest { $script:downloads++; throw 'Mock network download failure' }
function Stop-Service { throw 'Unexpected service change before valid downloads' }
function New-ItemProperty { throw 'Unexpected registry change before valid downloads' }
function New-NetFirewallRule { throw 'Unexpected firewall change before valid downloads' }
$script:downloads=0
Assert (-not (Invoke-ToolkitRdpWrapper)) 'RDP download failure reported success'
Assert ($script:downloads -eq 1) 'RDP test did not reach the expected download failure'
Write-Output 'PASS RDP download failure leaves services/registry/firewall unchanged'
# Exercise successful setup and failure after configuration changes, with all writes mocked.
$script:registry=@{fDenyTSConnections=1;UserAuthentication=1;ServiceDll='%SystemRoot%\System32\termsrv.dll'}
function Get-ToolkitRdpWrapperDll { param($Directory,$Architecture) $path=Join-Path $Directory 'candidate.dll';$script:files[$path]=$true;return $path }
$script:original=@{};foreach($key in $script:registry.Keys){$script:original[$key]=$script:registry[$key]}
$script:files=@{};$script:rule=$false;$script:starts=0;$script:listener=$true;$script:startType='Manual'
function Test-Path { param($LiteralPath,$PathType) return $script:files.ContainsKey($LiteralPath) }
function Get-Item {
    param($LiteralPath,$ErrorAction)
    $k=New-Object psobject
    $k | Add-Member ScriptMethod GetValueNames { @($script:registry.Keys) }
    $k | Add-Member ScriptMethod GetValue { param($Name,$Default,$Options) $script:registry[$Name] }
    $k | Add-Member ScriptMethod GetValueKind { param($Name) if($Name -eq 'ServiceDll'){'ExpandString'}else{'DWord'} }
    return $k
}
function Get-Service {
    param($Name,$ErrorAction)
    $svc=[pscustomobject]@{Status='Running'}
    $svc | Add-Member ScriptMethod WaitForStatus { param($Status,$Timeout) }
    return $svc
}
function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction) $script:files[$OutFile]=$true }
function Select-String { param($LiteralPath,$Pattern,[switch]$Quiet) $true }
function Get-ToolkitPeArchitecture { param($Path) if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE} }
function Copy-Item { param($LiteralPath,$Destination,[switch]$Force,$ErrorAction) $script:files[$Destination]=$true }
function Remove-Item { param($LiteralPath,[switch]$Force,$ErrorAction) $script:files.Remove($LiteralPath) | Out-Null }
function Stop-Service { param($Name,[switch]$Force,$ErrorAction) }
function Start-Service { param($Name,$ErrorAction) $script:starts++ }
function Set-Service { param($Name,$StartupType,$ErrorAction) $script:startType=$StartupType }
function New-ItemProperty { param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) $script:registry[$Name]=$Value }
function Get-ItemPropertyValue { param($LiteralPath,$Name,$ErrorAction) $script:registry[$Name] }
function New-NetFirewallRule { param($Name,$DisplayName,$Direction,$Action,$Protocol,$LocalPort,$Profile,$ErrorAction) $script:rule=$true }
function Remove-NetFirewallRule { param($Name,$ErrorAction) $script:rule=$false }
function Test-NetConnection { param($ComputerName,$Port,$InformationLevel,$WarningAction,$ErrorAction) $script:listener }
Assert (Invoke-ToolkitRdpWrapper) 'RDP successful listener check failed'
Assert ($script:registry.UserAuthentication -eq 1 -and $script:rule) 'RDP success did not retain NLA/firewall'
$script:files=@{};$script:rule=$false;$script:registry=@{};foreach($key in $script:original.Keys){$script:registry[$key]=$script:original[$key]}
$script:listener=$false;$script:starts=0
Assert (-not (Invoke-ToolkitRdpWrapper)) 'Missing RDP listener was reported as success'
foreach($key in $script:original.Keys){Assert ($script:registry[$key] -ceq $script:original[$key]) "RDP rollback failed: $key"}
Assert (-not $script:rule -and $script:startType -eq 'Manual' -and $script:starts -eq 2) 'RDP rollback did not restore firewall/startup/running state'
Write-Output 'PASS RDP success verification and listener-failure rollback of registry/firewall/service state'
$text=$ast.Extent.Text
Assert (-not $text.Contains('sc.exe delete')) 'Destructive antivirus service deletion remains'
Assert (-not $text.Contains('Remove-CimInstance')) 'Antivirus WMI suppression remains'
Assert (-not $text.Contains('Add-MpPreference')) 'Automatic Defender exclusions remain'
Assert (-not $text.Contains('Anonymous Full Access')) 'Anonymous share workflow remains'
Write-Output 'PASS no legacy AV purge, automatic Defender exclusions or anonymous share workflow'
Write-Output "Synthetic fixtures retained in $testDir"
