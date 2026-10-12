$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Test-ToolkitPrinterShareName','Invoke-ToolkitPrinterConnectionDiagnostic')) {
    $f=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $f){throw "Missing $name"}; Invoke-Expression $f.Extent.Text
}
function Test-NetConnection { param($ComputerName,$Port,$InformationLevel,$WarningAction,$ErrorAction) $false }
function Get-Service { param($Name,$ErrorAction) [pscustomobject]@{Status='Running'} }
function Get-PrinterDriver { param($ErrorAction) [pscustomobject]@{Name='Mock signed driver'} }
function Get-Printer { param($Name,$ComputerName,$ErrorAction) if($script:connected){[pscustomobject]@{Name=$Name}} }
function Set-Content { param($LiteralPath,$Value,$Encoding,$ErrorAction) $script:reports++ }
function Add-Content { param($LiteralPath,$Value,$Encoding,$ErrorAction) $script:logged++ }
function Start-Service { throw 'Unexpected service mutation' }
function Start-Process { throw 'Unexpected GUI launch' }
function Read-Host { param($Prompt) $script:answers.Dequeue() }
function Add-Printer { param($ConnectionName,$ErrorAction) $script:adds++; if($script:fail){throw 'Mock access denied'}; $script:connected=$true }
$script:reports=0;$script:logged=0;$script:adds=0;$script:connected=$false
$script:answers=[Collections.Generic.Queue[string]]::new();$script:answers.Enqueue('0')
Invoke-ToolkitPrinterConnectionDiagnostic -HostName '127.0.0.1' -ShareName 'Printer_Test'
if($script:reports -ne 1 -or $script:adds){throw 'Cancelled diagnosis mutated state'}
Write-Output 'PASS diagnosis and cancel'
$script:answers.Enqueue('6');$script:fail=$false
Invoke-ToolkitPrinterConnectionDiagnostic -HostName '127.0.0.1' -ShareName 'Printer_Test'
if($script:adds -ne 1 -or -not $script:connected){throw 'Retry success not verified'}
Write-Output 'PASS verified retry'
$script:connected=$false;$script:fail=$true;$script:answers.Enqueue('6');$script:answers.Enqueue('0')
Invoke-ToolkitPrinterConnectionDiagnostic -HostName '127.0.0.1' -ShareName 'Printer_Test'
if($script:logged -ne 1 -or $script:connected){throw 'Failed retry logging incorrect'}
Write-Output 'PASS failure logged without false success'
$count=$script:reports
Invoke-ToolkitPrinterConnectionDiagnostic -HostName 'bad/host' -ShareName 'Printer_Test'
if($script:reports -ne $count){throw 'Invalid input not rejected'}
Write-Output 'PASS input validation; no real printer/registry/credential/network changes'
