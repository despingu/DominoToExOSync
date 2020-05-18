$exportRunScript = Join-Path $PSScriptRoot "runexport.ps1"
$importRunScript = Join-Path $PSScriptRoot "runimport.ps1"
$startTime = Get-Date

#start x86 powershell for notes export
Start-Process "$env:SystemRoot\syswow64\WindowsPowerShell\v1.0\powershell.exe" -Wait -ArgumentList "-File `"$exportRunScript`""
$exportTime = Get-Date
$runTime = $exportTime - $startTime
Write-Host "Time elapsed for Export: $($runTime.ToString("hh\:mm\:ss"))"

Start-Process "Powershell.exe" -Wait -ArgumentList "-File `"$importRunScript`""
$importTime = Get-Date
$runTime = $importTime - $exportTime
$totalRunTime = $importTime -$startTime

Write-Host "Time elapsed for Import: $($runTime.ToString("hh\:mm\:ss"))"
Write-Host "Total time elapsed: $($totalRunTime.ToString("hh\:mm\:ss"))"