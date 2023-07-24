##################################################################################
## Grants the Function app identity the role assignments on the storage account ##
## required by the Azure Table Backup solution                                  ##
##################################################################################

## Check required modules
#Requires -Modules Az.Accounts,Az.Resources

$Tenant = "<tenantId>"# The ID of the tenant containing your Azure subscription
$Subscription = "<subscriptionName>" # The name of the Azure subscription which hosts your resources
$StorageAccountName = "<storageAccountName" # The name of the storage account containing the tables you want to backup

# Connect to Azure AD
try 
{
    $Connection = Connect-AzAccount -Subscription $Subscription -Tenant $Tenant -ErrorAction Stop
}
catch 
{
    throw $_.Exception.Message
}

# Locate the storage account resource
try 
{
    $StorageAccount = Get-AzResource `
        -Name "$StorageAccountName" `
        -ResourceType "Microsoft.Storage/storageAccounts" `
        -ErrorAction Stop
}
catch 
{
    throw $_.Exception.Message.Split([Environment]::NewLine)[0]
}
If ($null -eq $StorageAccount)
{
    throw "Storage account not found! Check the name."
}

# Locate the function app resource
try 
{
    $FunctionApp = Get-AzResource `
        -Name "func-azTableBackup*" `
        -ResourceType "Microsoft.Web/sites" `
        -ResourceGroupName "rg-azTableBackup*" `
        -ErrorAction Stop
}
catch 
{
    throw $_.Exception.Message.Split([Environment]::NewLine)[0]
}
If ($null -eq $FunctionApp)
{
    throw "Function app not found!"
}

# Add the role assignments
Write-Host "Adding role assignments for function app system identity to storage account..."
"Storage Table Data Reader","Storage Blob Data Contributor" | foreach {
    Write-Host "  $_..." -NoNewline
    try 
    {
        $RoleAssignment = New-AzRoleAssignment `
        -ObjectId $FunctionApp.Identity.PrincipalId `
        -RoleDefinitionName "$_" `
        -Scope $StorageAccount.Id `
        -WarningAction SilentlyContinue `
        -ErrorAction Stop
        Write-Host "Success!" -ForegroundColor Green
    }
    catch 
    {
        Write-Host "Failed!" -ForegroundColor Red
        Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    }
}