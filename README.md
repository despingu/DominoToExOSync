# DominoToExOSync
Scripts to synchronize distribution groups and other to from a Domino environment to Exchange Online

# Prerequisites
The import script requires the AzureADPreview PowerShell module and the ExchangeOnlineManagement PowerShell Module in stored in a subfolder $PSSCriptRoot\Modules

If you have these modules installed, save them locally by running these commands:
```powershell
Save-Module -Name AzureADPreview -Path "pathToScript\Modules"
Save-Module -Name ExchangeOnlineManagement -Path "pathToScript\Modules"
```
