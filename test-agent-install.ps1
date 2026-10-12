$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.ServiceProcess
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$f=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-ToolkitAgent'},$true)
Invoke-Expression $f.Extent.Text
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$native=if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE}
function New-Item { param($ItemType,$Path,[switch]$Force,$ErrorAction) }
function Get-Item { param($LiteralPath,$ErrorAction) [pscustomobject]@{Name='meshagent.exe';Length=4096} }
function Copy-Item { param($LiteralPath,$Destination,[switch]$Force,$ErrorAction) $script:copies+=$Destination }
function Move-Item { param($LiteralPath,$Destination,$ErrorAction) }
function Get-FileHash { param($LiteralPath,$Algorithm,$ErrorAction) [pscustomobject]@{Hash=$(if($script:badCopy -and $LiteralPath -like '*.partial'){'different'}else{'same'})} }
function Get-ToolkitPeArchitecture { param($Path) if($script:badArch){'unsupported'}else{$native} }
function Get-ToolkitMeshSettings { param($Path) @{MeshID='g';ServerID='s';MeshServer='wss://example.test/agent.ashx'} }
function Test-Path { param($LiteralPath,$PathType) if($LiteralPath -like '*.msh'){return $script:sidecar};return $true }
function Start-Process { param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru,$ErrorAction) $script:launches++;$script:args=$ArgumentList;[pscustomobject]@{ExitCode=$script:exitCode} }
function Get-Service { param($Name,$ErrorAction) $s=[pscustomobject]@{Status='Running'}; $s|Add-Member ScriptMethod WaitForStatus {param($Status,$Timeout)};return $s }
function Start-Service { throw 'Unexpected service start in these fixtures' }
function Test-ToolkitMeshRuntime { param($ServiceName,$Expected,$Stage) $script:checks++;if($script:runtimeFailure){throw 'Mock stale/wrong-group Mesh service'} }
function Remove-Item { param($LiteralPath,[switch]$Force,[switch]$Recurse,$ErrorAction) if($Recurse){$script:cleaned++} }
foreach($case in @('success','sidecar','badcopy','badarch','exitfailure','reboot','runtimefailure')) {
    $script:badCopy=$case -eq 'badcopy';$script:badArch=$case -eq 'badarch';$script:sidecar=$case -eq 'sidecar'
    $script:runtimeFailure=$case -eq 'runtimefailure';$script:copies=@();$script:launches=0;$script:checks=0;$script:cleaned=0;$script:args=''
    $script:exitCode=switch($case){'exitfailure'{5} 'reboot'{3010} default{0}}
    $result=Install-ToolkitAgent -Installer 'D:\Fixture\meshagent.exe' -Arguments '-fullinstall' -ServiceName 'Mesh Agent'
    Assert ($result -eq ($case -in @('success','sidecar'))) "Incorrect result: $case"
    if($case -in @('badcopy','badarch')){Assert ($script:launches -eq 0) "Invalid executable launched: $case"}
    if($case -eq 'reboot'){Assert ($script:cleaned -eq 0 -and $script:checks -eq 0) 'Reboot case deleted installer or falsely verified runtime'}
    if($case -in @('exitfailure','runtimefailure')){Assert ($script:cleaned -eq 0) "Failed installer was deleted: $case"}
    if($case -eq 'sidecar'){Assert ($script:args -like '*--copy-msh=1*' -and @($script:copies | Where-Object {$_ -like '*.msh'}).Count -eq 1) 'Sidecar policy was not staged/passed to installer'}
    Write-Output "PASS mocked Mesh install: $case"
}
