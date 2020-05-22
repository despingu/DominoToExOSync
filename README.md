# DominoToExOSync

Scripts to synchronize distribution groups and other from a Domino environment to Exchange Online

## Prerequisites  

### Export-NotesGroupsToXML  

The prerequisites to run the export script are explained [in this blog article](https://cloudandreas.wordpress.com/2017/02/14/using-powershell-to-connect-to-lotus-notes-com-object/).

### Import-GroupsXmlToExO  

You need to provide an account with at least Exchange Online Administrator privileges.

## Common Information

The two scripts `Export-NotesGroupsToXML.ps1` and `Import-GroupsXmlToExO.ps1` can be called directly.
To automate script calls in a task schedule the you need to call the `run.ps1` script.
The `run.ps1` script will call two individual run scripts for the import and export processes.
This is necessary because the Notes export needs an x86 PowerShell process to run and this way its easier to call a script with parameters in its own process.
