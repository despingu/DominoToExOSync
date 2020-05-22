param(
    [parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$DominoServer,
    [parameter(Mandatory = $true, Position = 1)][ValidateNotNullOrEmpty()][string]$Database,
    [parameter(Mandatory = $true, Position = 2)][ValidateNotNullOrEmpty()][string]$XmlFilePath,
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
    $msgToLog = "[$(Get-Date -Format "yyyy-MM-dd HH-mm-ss")] [$level] [$msg]"
    Out-File -FilePath $logFilePath -Encoding utf8 -InputObject $msgToLog -Append -Force
    If ($LogToScreen) {
        Switch ($level) {
            'Info'      {Write-Host $msgToLog}
            'Error'     {Write-Host $msgToLog -ForegroundColor red}
            'Warning'   {Write-Host $msgToLog -ForegroundColor yellow}
        }
    }
}

function Get-GroupType {
    param(
        [int]$groupTypeId
    )

    $groupType = $null
    switch ($groupTypeId) {
        0 { $groupType = "MultiPurpose" }
        1 { $groupType = "MailOnly" }
        2 { $groupType = "AccessControlListOnly" }
        3 { $groupType = "DenyListOnly" }
        4 { $groupType = "ServersOnly" }
    }
    return $groupType
}

#init xml
function Add-XmlAttribute {
    param (
        [String]$AttributeName,
        [String]$AttributeValue,
        [System.Xml.XmlNode]$ParentNode,
        [System.Xml.XmlDocument]$Document
    )
    $attribute = $Document.CreateAttribute($AttributeName)
    $attribute.Value = $AttributeValue
    $ParentNode.Attributes.Append($attribute) | out-null
}

function Add-XmlElementValue {
    param(
        [string]$ElementName,
        [string]$ElementValue,
        [System.Xml.XmlNode]$ParentNode,
        [System.Xml.XmlDocument]$Document
    )
    $xmlValueElement = $Document.CreateNode("element", $ElementName, $null)
    Add-XmlAttribute -AttributeName "Value" -AttributeValue $ElementValue -ParentNode $xmlValueElement -Document $Document
    $ParentNode.AppendChild($xmlValueElement) | out-null
}

function Add-XmlArray {
    param (
        [Array]$Values,
        [String]$ElementName,
        [System.Xml.XmlNode]$ParentNode,
        [System.Xml.XmlDocument]$Document
    )
    $parentElement = $xmlDocument.CreateNode("element", "$($ElementName)s", $null)
    $ParentNode.AppendChild($parentElement) | out-null

    foreach ($value in $Values) {
        Add-XmlElementValue -ElementName $ElementName -ElementValue $value -ParentNode $parentElement -Document $Document
    }
}

[xml]$xmlDocument = New-Object System.Xml.XmlDocument
$xmlDocument.AppendChild($xmlDocument.CreateXmlDeclaration("1.0", "UTF-8", $null)) | out-null
$initComment = @"

Notes Group export
Author: David Espin, Marc Jonas
Script Date: 04/2020
Generated: $(Get-Date)

"@
$xmlDocument.AppendChild($xmlDocument.CreateComment($initComment)) | out-null
$xmlRootElement = $xmlDocument.createNode("element", "DominoEnvironment", $null)
Add-XmlAttribute -AttributeName "Server" -AttributeValue $DominoServer -ParentNode $xmlRootElement -Document $xmlDocument
Add-XmlAttribute -AttributeName "Database" -AttributeValue $Database -ParentNode $xmlRootElement -Document $xmlDocument
$xmlDocument.AppendChild($xmlRootElement) | out-null
$xmlGroupsElement = $xmlDocument.createNode("element", "Groups", $null)
$xmlRootElement.AppendChild($xmlGroupsElement) | out-null

#end init xml

$_LogFileName = "Export-NotesGroupsToXML_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"

if ([Environment]::Is64BitProcess -eq $true) { 
    New-LogMsg "PowerShell is a 64 bit process. 32 bit process needed. Exiting script." Error
    exit 
} #because you have a 64-bit PowerShell

$notesSession = $null
$notesAdressbook = $null
$groupsView = $null
$usersView = $null
$groupDocument = $null

try {
    $notesSession = New-Object -ComObject Lotus.NotesSession #open the Notes Session
    $notesSession.Initialize("") #if no password is provided, Notes will ask for the password
    $notesAdressbook = $notesSession.GetDatabase($DominoServer, $Database, 0)
}
catch {
    New-LogMsg "Could not establish Notes session." Error
    New-LogMsg  "Error Message: $($_.Exception.Message)" Error
    exit
}

try {
    $groupsView = $notesAdressbook.GetView("(`$VIMGroups)")
}
catch {
    New-LogMsg "Could not get groups view." Error
    New-LogMsg  "Error Message: $($_.Exception.Message)" Error
    exit
}

try {
    $usersView = $notesAdressbook.GetView("(`$VIMPEOPLE)")
}
catch {
    New-LogMsg "Could not get users view." Error
    New-LogMsg  "Error Message: $($_.Exception.Message)" Error
    exit
}

try {
    $groupDocument = $groupsView.GetFirstDocument()
}
catch {
    New-LogMsg "Could not get first group document." Error
    New-LogMsg  "Error Message: $($_.Exception.Message)" Error
    exit
}

while ($null -ne $groupDocument) {
    try {
        $groupName = $groupDocument.GetItemValue("ListName")[0]
        $groupSMTP = $groupDocument.GetItemValue("InternetAddress")[0]
        $groupType = Get-GroupType -GroupTypeId ($groupDocument.GetItemValue("GroupType")[0])

        New-LogMsg -level Info -msg "Started processing group $groupName."
        $xmlGroupElement = $xmlDocument.CreateNode("element", "Group", $null)
        Add-XmlAttribute -AttributeName "Name" -AttributeValue $groupName -ParentNode $xmlGroupElement -Document $xmlDocument
        Add-XmlAttribute -AttributeName "SmtpAddress" -AttributeValue $groupSMTP -ParentNode $xmlGroupElement -Document $xmlDocument
        Add-XmlAttribute -AttributeName "Type" -AttributeValue $groupType -ParentNode $xmlGroupElement -Document $xmlDocument
        $xmlGroupsElement.AppendChild($xmlGroupElement) | out-null
        $groupMembers = $groupDocument.GetItemValue("Members")
    
        if ($null -ne $groupMembers) {
            $xmlInternalMembersElement = $xmlDocument.CreateNode("element", "InternalMembers", $null)
            $xmlGroupMembersElement = $xmlDocument.CreateNode("element", "GroupMembers", $null)
            $xmlUnresolvedMembersElement = $xmlDocument.CreateNode("element", "UnresolvedMembers", $null)
            $xmlExternalMembersElement = $xmlDocument.CreateNode("element", "ExternalMembers", $null)
            $xmlGroupElement.AppendChild($xmlInternalMembersElement) | out-null
            $xmlGroupElement.AppendChild($xmlGroupMembersElement) | out-null
            $xmlGroupElement.AppendChild($xmlUnresolvedMembersElement) | out-null
            $xmlGroupElement.AppendChild($xmlExternalMembersElement) | out-null
            foreach ($member in $groupMembers) {
                New-LogMsg -level Info -msg "Working on member $member."
                $notesName = $notesSession.CreateName($member)
                if ($notesName.IsHierarchical) {
                    # case internal member
                    $personDocument = $usersView.GetDocumentByKey($notesName.Abbreviated, $true)
                    if ($null -ne $personDocument) {
                        $primarySMTPAddress = $personDocument.GetItemValue("InternetAddress")[0]
                        if([String]::IsNullOrEmpty($primarySMTPAddress)) {
                            New-LogMsg "Member $member has no primary SMTP address" Warning
                        }
                        $notesShortNames = $personDocument.GetItemValue("ShortName")
                        $notesFullNames = $personDocument.GetItemValue("FullName")

                        $xmlInternalMemberElement = $xmlDocument.CreateNode("element", "InternalMember", $null)
                        Add-XmlAttribute -AttributeName "PrimarySMTPAddress" -AttributeValue $primarySMTPAddress -ParentNode $xmlInternalMemberElement -Document $xmlDocument
                        Add-XmlArray -Values $notesShortNames -ElementName "ShortName" -ParentNode $xmlInternalMemberElement -Document $xmlDocument
                        Add-XmlArray -Values $notesFullNames -ElementName "FullName" -ParentNode $xmlInternalMemberElement -Document $xmlDocument
                        $xmlInternalMembersElement.AppendChild($xmlInternalMemberElement) | out-null
                    }
                    else {
                        # user could not be resolved
                        Add-XmlElementValue -ElementName "UnresolvedMember" -ElementValue $member -ParentNode $xmlUnresolvedMembersElement -Document $xmlDocument
                    }
                }
                else {
                    # group or external?
                    $groupAsMemberDocument = $groupsView.GetDocumentByKey($member, $true)
                    if ($null -ne $groupAsMemberDocument) {
                        # member is a group
                        $groupType = Get-GroupType -GroupTypeId $groupAsMemberDocument.GetItemValue("GroupType")[0]
                        $xmlGroupMemberElement = $xmlDocument.CreateNode("element", "GroupMember", $null)
                        Add-XmlAttribute -AttributeName "Name" -AttributeValue $member -ParentNode $xmlGroupMemberElement -Document $xmlDocument
                        Add-XmlAttribute -AttributeName "Type" -AttributeValue $groupType -ParentNode $xmlGroupMemberElement -Document $xmlDocument
                    }
                    elseif ($member -like "*@*") {
                        #member is external
                        Add-XmlElementValue -ElementName "ExternalMember" -ElementValue $member -ParentNode $xmlExternalMembersElement -Document $xmlDocument
                    }
                }
            }
        }
        else {
            New-LogMsg -level Info -msg "Group $groupName has no members."
        }
        New-LogMsg -level Info -msg "Finished processing group $groupName."
    }
    catch {
        New-LogMsg "Error processing Group." Error
        New-LogMsg  "Error Message: $($_.Exception.Message)" Error
    }
    finally {
        $xmlDocument.Save($XmlFilePath)
    }
    $groupDocument = $groupsView.GetNextDocument($groupDocument)
}