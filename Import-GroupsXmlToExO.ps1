param(
    [parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$XmlSourceFilePath,
    [parameter(Mandatory = $true, Position = 1)][ValidateNotNullOrEmpty()][string]$User,
    [parameter(Mandatory = $true, Position = 2)][ValidateNotNullOrEmpty()][securestring]$Password,
    [parameter(Mandatory = $true, Position = 3)][ValidateNotNullOrEmpty()][string]$LogPath,
    [parameter(Mandatory = $false)][switch]$LogToScreen,
    [parameter(Mandatory = $false)][string]$TargetGroupDomain
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
    $msgToLog = "[$(Get-Date -Format "yyyy-MM-dd HH-mm-ss")] [$level] [$msg]"
    Out-File -FilePath $logFilePath -Encoding utf8 -InputObject $msgToLog -Append -Force
    If ($LogToScreen) {
        Switch ($level) {
            'Info' { Write-Host $msgToLog }
            'Error' { Write-Host $msgToLog -ForegroundColor red }
            'Warning' { Write-Host $msgToLog -ForegroundColor yellow }
        }
    }
}

function Ensure-DistributionGroup {
    param(
        [string]$Name,
        [String]$SmtpAddress
    )

    if (-not [string]::IsNullOrEmpty($SmtpAddress)) {
        $domainPattern = "(((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)+(xn--)?([a-z0-9][a-z0-9\-]{0,60}|[a-z0-9-]{1,30}\.[a-z]{2,})"
        $mailAddressPattern = "[A-Za-z0-9._%+-]+@$domainPattern"
        if($SmtpAddress -match $mailAddressPattern) {
            if (-not [string]::IsNullOrEmpty($TargetGroupDomain)) {
                $newSmtpAddress = $SmtpAddress -replace "@$domainPattern", "@$TargetGroupDomain"
                New-LogMsg -msg "Smtp addresss $smtpaddress will be replaced with $newSmtpAddress." -level Info
                $SmtpAddress = $newSmtpAddress
            }
        }
        else {
            New-LogMsg -msg "Group smtp address $SmtpAddress is not a valid address and will be ignored." -level Warning
            $SmtpAddress = $null
        }
    }


    $distributionGroup = $null
    $distributionGroup = Get-DistributionGroup -Identity $Name -ErrorAction SilentlyContinue
    if ($null -eq $distributionGroup) {
        New-LogMsg -msg "Distribution group $($Name) not found." -level Info
        New-LogMsg -msg "Creating distribution group $($Name)." -level Info
        #if no distribution group exists, create one
        try {
            if ([string]::IsNullOrEmpty($SmtpAddress)) {
                $distributionGroup = New-DistributionGroup -DisplayName $Name -Name $Name -Type Distribution -MemberJoinRestriction Closed -MemberDepartRestriction Closed
            }
            else {
                $distributionGroup = New-DistributionGroup -DisplayName $Name -Name $Name -Type Distribution -PrimarySmtpAddress $SmtpAddress -MemberJoinRestriction Closed -MemberDepartRestriction Closed
            }
        }
        catch {
            New-LogMsg -msg "Error creating distribution group $($Name)." -level Error
            New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
        }
    }
    return $distributionGroup
}

function Get-InternalMembers {
    param(
        [array]$InternalMembers
    )
    $members = @()

    foreach ($internalMember in $InternalMembers) {
        $primarySmtpAddress = $internalMember.PrimarySMTPAddress
        if (-not [String]::IsNullOrEmpty($primarySmtpAddress)) {
            $azureADuser = Get-AzureADUser -SearchString $primarySmtpAddress
            if ($null -ne $azureADuser) {
                if ($azureADuser -isnot [array]) {
                    $members += $azureADUser.UserPrincipalName
                }
                else {
                    New-LogMsg -msg "No unique user with primary smtp address $primarySmtpAddress found in Azure AD. Skipping user." -level Warning
                    continue
                }
            }
            else {
                New-LogMsg -msg "No user with primary smtp address $primarySmtpAddress found in Azure AD. Skipping user." -level Warning
                continue
            }
        }
        else {
            New-LogMsg -msg "Group contains a member without primary SMTP address. Skipping user." -level Warning
            continue
        }
    }

    return $members
}

function Get-GroupMembers {
    param(
        [array]$GroupMembers,
        [switch]$EnsureGroups
    )
    $members = @()

    foreach ($groupMember in $GroupMembers) {
        if ($groupMember.Type -ne "MultiPurpose" -and $groupMember.Type -ne "MailOnly") {
            New-LogMsg -msg "Group member $($groupMember.Name) is of type $($groupMember.Type) and will be ignored." -level Info
            continue
        }

        if (-not [String]::IsNullOrEmpty($groupMember.Name)) {
            $azureADGroup = $null
            $searchResult = Get-AzureADGroup -searchString $groupMember.Name

            if ($searchResult -is [array]) {
                # check if array contains exact name
                foreach ($result in $searchResult) {
                    if ($result.DisplayName -eq $groupMember.Name) {
                        $azureADGroup = $result
                    }
                }
                
                if ($null -eq $azureADGroup) {
                    New-LogMsg -msg "No unique group with name $($groupMember.Name) found in Azure AD. Skipping group." -level Warning
                    continue
                }
            }
            else {
                $azureADGroup = $searchResult
            }

            if ($null -ne $azureADGroup) {
                if ($azureADGroup.MailEnabled) {
                    $members += $azureADGroup.Mail
                }
                else {
                    New-LogMsg -msg "name $($groupMember.Name) found as group in Azure AD, but is not mail enabled. Skipping group." -level Warning
                    continue
                }
            }
            elseif ($EnsureGroups) {
                $newDistributionGroup = Ensure-DistributionGroup -Name $groupMember.Name -SmtpAddress $groupMember.SmtpAddress
                $members += $newDistributionGroup.PrimarySmtpAddress
            }
            else {
                New-LogMsg -msg "No group with name $($groupMember.Name) found in Azure AD. Skipping group." -level Warning
                continue
            }
        }
        else {
            New-LogMsg -msg "Group contains a group member without names. Skipping group." -level Warning
            continue
        }
    }

    return $members
}

function Get-ExternalMembers {
    param(
        [array]$ExternalMembers
    )
    $members = @()

    foreach ($externalMember in $ExternalMembers) {
        $value = $externalMember.value
        if (-not [String]::IsNullOrEmpty($value)) {
            $azureADuser = Get-AzureADUser -SearchString $value
            if ($null -ne $azureADuser) {
                if ($azureADuser -isnot [array]) {
                    $members += $azureADUser.UserPrincipalName
                }
                else {
                    New-LogMsg -msg "No unique user with value $value found in Azure AD. Skipping user." -level Warning
                    continue
                }
            }
            else {
                $azureADGroup = Get-AzureADGroup -searchString $value
                if ($azureADGroup -isnot [array]) {
                    if ($null -ne $azureADGroup) {
                        if ($azureADGroup.MailEnabled) {
                            $members += $azureADGroup.Mail
                        }
                        else {
                            New-LogMsg -msg "Value $value found as group in Azure AD, but is not mail enabled. Skipping group." -level Warning
                            continue
                        }
                    }
                    else {
                        New-LogMsg -msg "No user or group with value $value found in Azure AD. Skipping user." -level Warning
                        continue
                    }
                }
            }
        }
        else {
            New-LogMsg -msg "Group contains an external member without value. Skipping user." -level Warning
            continue
        }
    }
    return $members
}

function Import-MembersToDistributionGroup {
    param(
        [array]$Members,
        $Group
    )
    New-LogMsg -msg "Updating Distribution group $($Group.Identity)." -level Info

    try {
        Update-DistributionGroupMember -Identity $Group.Identity -Members $Members -Confirm:$false
    }
    catch {
        New-LogMsg -msg "Error occured while Updating distribution group $($Group.Identity)." -level Error
        New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    } 
}

$aadModulePath = Join-Path $PSScriptRoot "Modules\AzureADPreview"
$exoModulePath = Join-Path $PSScriptRoot "Modules\ExchangeOnlineManagement"
Import-Module $exoModulePath
Import-Module $aadModulePath

$_LogFileName = "Import-GroupsXmlToExO_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"
$userCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password

# $exoSession = $null
New-LogMsg -msg "Connect to Exchange online." -level Info
try {
    $proxyOptions = New-PSSessionOption -ProxyAccessType IEConfig
    # $exoSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection -SessionOption $ProxyOptions
    # Import-PSSession $exoSession -DisableNameChecking | Out-Null

    Connect-ExchangeOnline -Credential $userCredential -PSSessionOption $proxyOptions | out-null
}
catch {
    New-LogMsg -msg "Error connecting to Exchange Online." -level Error
    New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    # if ($null -ne $exoSession) {
    #     Remove-PSSession $exoSession
    # }
    exit
}

try {
    New-LogMsg -msg "Connect to AzureAD." -level Info
    Connect-AzureAD -Credential $userCredential | Out-Null
}
catch {
    New-LogMsg -msg "Error connecting to AzureAD." -level Error
    New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    # if ($null -ne $exoSession) {
    #     Remove-PSSession $exoSession
    # }
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
    # if ($null -ne $exoSession) {
    #     Remove-PSSession $exoSession
    # }
    Disconnect-AzureAD
    exit
}

foreach ($group in $groups) {
    if ($group.Type -ne "MultiPurpose" -and $group.Type -ne "MailOnly") {
        New-LogMsg -msg "Group $($group.Name) is of type $($group.Type) and will be ignored." -level Info
        continue
    }

    try {
        New-LogMsg -msg "Processing group $($group.Name)." -level Info
        $members = @()
        if ($null -ne $group.InternalMembers.InternalMember) {
            $members += Get-InternalMembers -InternalMembers $group.InternalMembers.InternalMember
        }
        if ($null -ne $group.ExternalMembers.ExternalMember) {
            $members += Get-ExternalMembers -ExternalMembers $group.ExternalMembers.ExternalMember
        }
        if ($null -ne $group.GroupMembers.GroupMember) {
            $members += Get-GroupMembers -GroupMembers $group.GroupMembers.GroupMember -EnsureGroups
        }

        $distributionGroup = Ensure-DistributionGroup -Name $group.Name -SmtpAddress $group.SmtpAddress

        if ($null -ne $distributionGroup) {
            Import-MembersToDistributionGroup -Members $members -Group $distributionGroup
        }
        else {
            New-LogMsg -msg "Error while ensuring group $($group.Name)." -level Error
        }
    }
    catch {
        New-LogMsg -msg "Error processing group $($group.Name)." -level Error
        New-LogMsg -msg "Error Message: $($_.Exception.Message)" -level Error
    }
    New-LogMsg -msg "Finished processing group $($group.Name)." -level Info
}

# if ($null -ne $exoSession) {
#     Remove-PSSession $exoSession
# }
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-AzureAD