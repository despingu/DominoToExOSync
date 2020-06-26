function New-LogMsg {
    param(
        [parameter(Mandatory = $true, Position = 0)][string]$msg,
        [parameter(Mandatory = $true, Position = 1)][ValidateSet('Info', 'Error', 'Warning')][string]$level
    )
    
    if (-not (Test-Path $LogPath)) {
        New-Item $LogPath -ItemType Directory
    }

    $logFilePath = Join-Path -Path $LogPath -ChildPath $_LogFileName
    $msgToLog = "[$(Get-Date -Format "yyyy-MM-dd HH-mm-ss")]`t[$level]`t[$msg]"
    Out-File -FilePath $logFilePath -Encoding utf8 -InputObject $msgToLog -Append -Force
    If ($LogToScreen) {
        Switch ($level) {
            'Info' { Write-Host $msgToLog }
            'Error' { Write-Host $msgToLog -ForegroundColor red }
            'Warning' { Write-Host $msgToLog -ForegroundColor yellow }
        }
    }
}

$LogPath = Join-Path $PSScriptRoot "Logs"
$_LogFileName = "run_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"
$LogToScreen = $false

$exportRunScript = Join-Path $PSScriptRoot "runexport.ps1"
$importRunScript = Join-Path $PSScriptRoot "runimport.ps1"
$startTime = Get-Date

#start x86 powershell for notes export
Start-Process "$env:SystemRoot\syswow64\WindowsPowerShell\v1.0\powershell.exe" -Wait -ArgumentList "-File `"$exportRunScript`""
$exportTime = Get-Date
$runTime = $exportTime - $startTime
New-LogMsg "Time elapsed for Export: $($runTime.ToString("hh\:mm\:ss"))" Info

Start-Process "Powershell.exe" -Wait -ArgumentList "-File `"$importRunScript`""
$importTime = Get-Date
$runTime = $importTime - $exportTime
$totalRunTime = $importTime -$startTime

New-LogMsg "Time elapsed for Import: $($runTime.ToString("hh\:mm\:ss"))" Info
New-LogMsg "Total time elapsed: $($totalRunTime.ToString("hh\:mm\:ss"))" Info