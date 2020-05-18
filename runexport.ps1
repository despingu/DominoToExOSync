$exportScript = Join-Path $PSScriptRoot "Export-NotesGroupsToXML.ps1"
$DominoServer = "add/domino/server/here"
$Database = "names.nsf"
$XmlFilePath = Join-Path $PSScriptRoot "notesgroups.xml"
$LogPath = Join-Path $PSScriptRoot "Logs"
$LogToScreen = $true

Invoke-Expression ".'$exportScript' -DominoServer '$DominoServer' -Database '$Database' -XmlFilePath '$XmlFilePath' -LogPath '$LogPath' -LogToScreen:`$$LogToScreen"