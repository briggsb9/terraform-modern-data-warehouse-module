# terraform-modern-data-warehouse-module

Creates a modern Data Warehouse Architecture in Azure using managed identities for service to service authentication.

# Deployed Resources
* Resource Group
* Azure SQL Server with advanced data security and Azure AD authentication
* Staging Azure SQL Database
* Azure Synapse
* Data Factory configured with managed identity and linked services
* Data Lake with managed identity enabled
* Key Vault with access policy configured for Data Factory and Security admin Azure AD group
* Log Analytics Workspace for resource diagnostics and alerting
* Azure monitor action group for sql server vulnerability assessment and Data Factory notifications


![Image of components](URL)

# Variable Prerequisites
* Azure SQL server admin username and password
* Security admins Azure AD group id for access to Key Vault
* Azure AD SQL admin group id
* Azure AD tenant (Directory) id
* Notification email address


# Post Deployment
* Setup database level access for the Data Factory managed identity using something like:
  
    CREATE USER [dw-dev-df] FROM EXTERNAL PROVIDER
    EXEC sys.sp_addrolemember @rolename = N'db_owner', @membername = N'dw-dev-df'
