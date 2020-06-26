param(
    [parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$XmlSourceFilePath,
    [parameter(Mandatory = $true, Position = 1)][ValidateNotNullOrEmpty()][string]$User,
    [parameter(Mandatory = $true, Position = 2)][ValidateNotNullOrEmpty()][securestring]$Password,
    [parameter(Mandatory = $true, Position = 3)][ValidateNotNullOrEmpty()][string]$LogPath,
    [parameter(Mandatory = $false)][switch]$LogToScreen
)

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

$exoModulePath = Join-Path $PSScriptRoot "Modules\ExchangeOnlineManagement"
Import-Module $exoModulePath

$_LogFileName = "Remove-GroupsXmlFromExO_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"
$userCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password

New-LogMsg -msg "Connect to Exchange online." -level Info
try {
    $proxyOptions = New-PSSessionOption -ProxyAccessType IEConfig
    Connect-ExchangeOnline -Credential $userCredential -PSSessionOption $proxyOptions | out-null
}
catch {
    New-LogMsg -msg "Error connecting to Exchange Online." -level Error
    New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error

    Disconnect-ExchangeOnline -Confirm:$false
    exit
}

$groups = $null
try {
    New-LogMsg -msg "Get groups from $XmlSourceFilePath." -level Info
    [xml]$groupSource = Get-Content $XmlSourceFilePath
    $groups = $groupSource.DominoEnvironment.Groups.Group
}
catch {
    New-LogMsg -msg "Error getting groups from XML $XmlSourceFilePath." -level Error
    New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    Disconnect-ExchangeOnline -Confirm:$false
    exit
}

foreach ($group in $groups) {
    try {
        New-LogMsg -msg "Processing group $($group.Name)." -level Info
        if ($groupMember.Type -ne "MultiPurpose" -and $groupMember.Type -ne "MailOnly") {
            New-LogMsg -msg "Group member $($groupMember.Name) is of type $($groupMember.Type) and will be ignored." -level Info
            continue
        }

        $distributionGroup = $null
        $distributionGroup = Get-DistributionGroup -Identity $group.Name -ErrorAction SilentlyContinue
        if($null -ne $distributionGroup) {
            New-LogMsg -msg "Removing group $($distributionGroup.Name)." -level Info
            Remove-DistributionGroup -Identity '$distributionGroup.Name' -Confirm:$false
        }
        else {
            New-LogMsg -msg "Group $($group.Name) not found, skipping group." -level Info
        }
    }
    catch {
        New-LogMsg -msg "Error processing group $($group.Name)." -level Error
        New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    }
    New-LogMsg -msg "Finished processing group $($group.Name)." -level Info
}

Disconnect-ExchangeOnline -Confirm:$false