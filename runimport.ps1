$importScript = Join-Path $PSScriptRoot "Import-GroupsXmlToExO.ps1"
$XmlSourceFilePath = Join-Path $PSScriptRoot "notesgroups.xml"
$User = "exo-sync-acc@contoso.onmicrosoft.com"
# To get the encrypted password string use this command: ConvertTo-SecureString $password -AsPlainText -Force | ConvertFrom-SecureString
$encryptedPW = "add encrypted pw here"
$LogPath = Join-Path $PSScriptRoot "Logs"
$LogToScreen = $true
$TargetGroupDomain = "add target domain if applicable"

Invoke-Expression ".'$importScript' -XmlSourceFilePath '$XmlSourceFilePath' -User '$User' -Password (ConvertTo-SecureString '$encryptedPW') -LogPath '$LogPath' -LogToScreen:`$$LogToScreen -TargetGroupDomain '$TargetGroupDomain'"