# AzureTableBackup
## Automates Azure Table Storage backups to CSV files in an Azure storage account

Microsoft currently provides no native capability for backing up Azure table storage. If, therefore, you have any solutions that have a dependency on table storage your solution is at risk. Backing up table data means you can confidently store data in those tables without fear of some important information or configuration being accidentally deleted and unretrievable.

This solution provides an Azure function which will backup storage tables on a schedule that you can set, or on-demand. It works within an Azure subscription and across resource groups and multiple storage accounts, backing up table data to a container in the same storage account as the source table/s. It utilises a handy .Net library created by medienstudio which takes care of converting your table data to CSV format.

Point-in-time restores are easily performed using the Microsoft Azure Storage Explorer, which provides a GUI experience for importing CSV files into a storage table.

The solution is easily deployed using a PowerShell script to create and configure all the required Azure resources. The list of Azure tables you want to backup is itself contained in an Azure table, which is also backed-up by this solution. To add or remove tables in the backup, simply edit the configuration table.

The Azure function uses a timer trigger, and you can configure the backup schedule simply by editing the cron expression which is saved to an application setting in the Azure function app.

The Azure resources created by this solution are basically free to run as long as you remain within the tier limits. You obviously may incur some additional cost in your storage accounts for storing the backup files, and the cost depends on how many tables and how much data is in the tables that you are backing up, as well as how many backups you want to keep.

Full documentation can be found [here](https://docs.smsagent.blog/azure-solutions/automated-azure-table-storage-backups)https://docs.smsagent.blog/azure-solutions/automated-azure-table-storage-backups.
