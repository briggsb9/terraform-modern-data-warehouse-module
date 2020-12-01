# Create resource group

resource "azurerm_resource_group" "rg" {
  name     = "${var.service_short_name}-${var.environment_short_name}-RG"
  location = var.location
  tags     = merge(var.common_tags, var.solution_tags)
}

# Create Azure SQL Server

resource "azurerm_sql_server" "sql" {
  name                         = lower("${var.service_short_name}-${var.environment_short_name}-sql")
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql-admin-username
  administrator_login_password = var.sql-admin-password
  connection_policy            = "Proxy"

  tags = merge(var.common_tags, var.solution_tags)

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      extended_auditing_policy.0.storage_account_access_key
    ]
  }

  extended_auditing_policy {
    storage_endpoint                        = azurerm_storage_account.sqlassa.primary_blob_endpoint
    storage_account_access_key              = azurerm_storage_account.sqlassa.primary_access_key
    storage_account_access_key_is_secondary = false
    retention_in_days                       = 1
  }
}

# Fix MI assignment bug in terraform by running again using CLI

resource "null_resource" "sql_set_mi" {
  #triggers = { # Trigger to run every time
  #  always_run = "${timestamp()}"
  #}
  provisioner "local-exec" {
    command = "az sql server update --name ${azurerm_sql_server.sql.name} --resource-group ${azurerm_sql_server.sql.resource_group_name} --assign_identity"
  }
  depends_on = [
    azurerm_sql_server.sql,
  ]
}

# Set TLS to 1.2 only

resource "null_resource" "sql_set_tls" {
  #triggers = { # Trigger to run every time
  #  always_run = "${timestamp()}"
  #}
  provisioner "local-exec" {
    command = "az sql server update --name ${azurerm_sql_server.sql.name} --resource-group ${azurerm_sql_server.sql.resource_group_name} --minimal-tls-version 1.2"
  }
  depends_on = [
    azurerm_sql_server.sql,
  ]
}

# Enable Azure SQL Azure AD authentication for the Azure SQL Admin group

resource "azurerm_sql_active_directory_administrator" "sql" {
  server_name         = azurerm_sql_server.sql.name
  resource_group_name = azurerm_resource_group.rg.name
  login               = "Azure SQL Admin"
  tenant_id           = var.tenant-id
  object_id           = var.azuread_sql_admin_group_id
}

# Allow Azure services so Data Factory can connect without the use of a self-hosted integrated runtime

resource "azurerm_sql_firewall_rule" "sqlallowazureservices" {
  name                = "AllowAzureServices"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Azure SQL firewall rules

# Example VNet subnet rule

/*
resource "azurerm_sql_virtual_network_rule" "firewallsubnet" {
  name                = "AzureFirewallSubnet"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  subnet_id           = var.azure_firewall_subnet_id
}

# Example public IP rule

resource "azurerm_sql_firewall_rule" "silversands" {
  name                = "AllowSilversands"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  start_ip_address    = "213.120.82.188"
  end_ip_address      = "213.120.82.188"
}
*/

# Create storage account for SQL Advanced Security

resource "azurerm_storage_account" "sqlassa" {
  name                      = lower("${var.service_short_name}${var.environment_short_name}sqlassa")
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_replication_type  = "LRS"
  account_tier              = "Standard"
  enable_https_traffic_only = true

  tags = merge(var.common_tags, var.solution_tags)
}

# Set TLS to 1.2 only and disable public blob access on advanced data security storage account.

resource "null_resource" "as_set_tls" {
  #triggers = { # Trigger to run every time
  #  always_run = "${timestamp()}"
  #}
  provisioner "local-exec" {
    command = "az resource update --ids ${azurerm_storage_account.sqlassa.id} --set properties.minimumTlsVersion=TLS1_2 properties.allowBlobPublicAccess=false"
  }
  depends_on = [
    azurerm_storage_account.sqlassa,
  ]
}

# Create container for SQL Advanced Security

resource "azurerm_storage_container" "sqlassa" {
  name                  = "vascans"
  storage_account_name  = azurerm_storage_account.sqlassa.name
  container_access_type = "private"
}

# Prevent accidental/malicious deletion of the SQL auditing/logging storage account
/*
resource "azurerm_management_lock" "sqlassalock" {
  name       = "SQL Diagnostics Lock"
  scope      = azurerm_storage_account.sqlassa.id
  lock_level = "CanNotDelete"
  notes      = "Critical SQL Diagnosticd Storage Account"
}
*/

# Enable Azure SQL advanced data security

resource "azurerm_mssql_server_security_alert_policy" "sql" {
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  state               = "Enabled"
}

resource "azurerm_mssql_server_vulnerability_assessment" "sql" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.sql.id
  storage_container_path          = "${azurerm_storage_account.sqlassa.primary_blob_endpoint}${azurerm_storage_container.sqlassa.name}/"
  storage_account_access_key      = azurerm_storage_account.sqlassa.primary_access_key

  recurring_scans {
    enabled                   = true
    email_subscription_admins = false
    emails = [
      var.notificationemailaddress,
    ]
  }
}

# Create Azure SQL Databases

resource "azurerm_sql_database" "dwstagingdb" {
  name                = lower("${var.service_short_name}-staging-${var.environment_short_name}-db")
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.sql.name
  edition             = "Standard"
  tags                = merge(var.common_tags, var.solution_tags)

  lifecycle {
    prevent_destroy = true
  }
}

# Create Azure Synapse Database

resource "azurerm_sql_database" "synapsedb" {
  name                             = lower("${var.service_short_name}-${var.environment_short_name}-synapsesql")
  resource_group_name              = azurerm_resource_group.rg.name
  location                         = azurerm_resource_group.rg.location
  server_name                      = azurerm_sql_server.sql.name
  edition                          = "DataWarehouse"
  requested_service_objective_name = "DW100c"
  tags                             = merge(var.common_tags, var.solution_tags)

  lifecycle {
    prevent_destroy = true
  }
}

# Create Data Factory

resource "azurerm_data_factory" "datafactory" {
  name                = "${var.service_short_name}-${var.environment_short_name}-DF"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = merge(var.common_tags, var.solution_tags)

  lifecycle {
    ignore_changes = [
      vsts_configuration,
    ]
  }

  identity {
    type = "SystemAssigned"
  }
}

# Create linked services to ADL Gen 2. No Terraform support for other linked services using managed identities.

data "azurerm_client_config" "current" {
}

resource "azurerm_data_factory_linked_service_data_lake_storage_gen2" "example" {
  name                  = azurerm_storage_account.datalake.name
  resource_group_name   = azurerm_resource_group.rg.name
  data_factory_name     = azurerm_data_factory.datafactory.name
  use_managed_identity  = true
  tenant                = var.tenant_id
  url                   = azurerm_storage_account.datalake.primary_dfs_endpoint
}

# Create linked service to Key Vault

resource "azurerm_data_factory_linked_service_key_vault" "example" {
  name                = azurerm_key_vault.kv.name
  resource_group_name = azurerm_resource_group.rg.name
  data_factory_name   = azurerm_data_factory.datafactory.name
  key_vault_id        = azurerm_key_vault.kv.id
}

# Create Data Lake

resource "azurerm_storage_account" "datalake" {
  name                      = lower("${var.service_short_name}${var.environment_short_name}dl")
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_replication_type  = "LRS" # Discuss
  account_tier              = "Standard"
  enable_https_traffic_only = true
  is_hns_enabled            = true # Enables Data Lake features
  tags                      = merge(var.common_tags, var.solution_tags)
}

resource "azurerm_storage_account_network_rules" "datalake" {
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_name = azurerm_storage_account.datalake.name
  default_action       = "Deny"
  //ip_rules                   = ["82.5.183.85","176.254.209.100","86.191.16.136","82.3.77.241","213.120.82.188","79.71.176.157","90.248.185.223","31.125.194.184","90.220.150.68","134.213.1.135","2.221.82.235","90.248.213.90","92.245.151.74"]
  virtual_network_subnet_ids = [var.azure_firewall_subnet_id,var.gateway_subnet_id,]
  bypass                     = ["AzureServices"]

  lifecycle {
    ignore_changes = [
      ip_rules,
    ]
  }
}

# Set TLS to 1.2 only and disable public blob access. 

resource "null_resource" "dl_set_tls" {
  #triggers = { # Trigger to run every time
  #  always_run = "${timestamp()}"
  #}
  provisioner "local-exec" {
    command = "az resource update --ids ${azurerm_storage_account.datalake.id} --set properties.minimumTlsVersion=TLS1_2 properties.allowBlobPublicAccess=false"
  }
  depends_on = [
    azurerm_storage_account.datalake,
  ]
}

# Datalake role assignments

resource "azurerm_role_assignment" "dl_df_mi_blobcontributor" { # Data Factory Managed Identity
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.datafactory.identity[0].principal_id
}

resource "azurerm_role_assignment" "dl_sql_mi_blobcontributor" { # SQL Server Managed Identity
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_sql_server.sql.identity[0].principal_id
}

# Create Key Vault for Solution

resource "azurerm_key_vault" "kv" {
  name                            = "${var.service_short_name}-${var.environment_short_name}-KV"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  tenant_id                       = var.tenant-id
  soft_delete_enabled             = true
  purge_protection_enabled        = false
  enabled_for_template_deployment = true

  sku_name = "standard"
  tags = merge(var.common_tags, var.solution_tags)
}

resource "azurerm_key_vault_access_policy" "datafactory" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = azurerm_data_factory.datafactory.identity.0.tenant_id
  object_id = azurerm_data_factory.datafactory.identity.0.principal_id

  secret_permissions = [
    "get",
  ]

  key_permissions = [
    "list",
  ]
}

resource "azurerm_key_vault_access_policy" "security_admins" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = var.tenant-id
  object_id = var.security_admins_group_id

  secret_permissions = [
    "backup", "delete", "get", "list", "purge", "recover", "restore", "set"
  ]

  key_permissions = [
    "create", "decrypt", "delete", "encrypt", "get", "import", "list", "purge", "recover", "restore", "sign", "unwrapKey", "update", "verify", "wrapKey"
  ]

  certificate_permissions = [
    "backup", "create", "delete", "deleteissuers", "get", "getissuers", "import", "list", "listissuers", "managecontacts", "manageissuers", "purge", "recover", "restore", "setissuers", "update"
  ]
}