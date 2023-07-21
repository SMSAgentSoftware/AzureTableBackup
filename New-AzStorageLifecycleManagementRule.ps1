#####################################################################################################
## Creates a new lifecycle management policy for the table backups container used by this solution ##
#####################################################################################################

#! Run this for each storage account where you are backing up tables with this solution !#

# Set the parameters for the storage account
$azSubscription = "<MyAzureSubscription>"
$resourceGroupName = "<ResourceGroup>"
$storageAccountName = "<StorageAccount>"
$retentionPeriod = 180 # days
$backupContainerName = "tablebackups"
$ruleName = "Purge old table backups"

# Check for required modules
#Requires -Modules Az.Storage

# Authenticate with Azure AD
try 
{
    $null = Connect-AzAccount -Subscription $azSubscription -ErrorAction Stop
}
catch 
{
    throw "Authentication failure: $($_.Exception.Message)"    
}

# Create a new action object.
$action = Add-AzStorageAccountManagementPolicyAction -BaseBlobAction Delete -DaysAfterCreationGreaterThan $retentionPeriod

# Create a new filter object.
$filter = New-AzStorageAccountManagementPolicyFilter -PrefixMatch "$backupContainerName/" -BlobType blockBlob

# Create a new rule object.
$rule = New-AzStorageAccountManagementPolicyRule -Name $ruleName -Action $action -Filter $filter

# Create the policy.
Set-AzStorageAccountManagementPolicy -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -Rule $rule