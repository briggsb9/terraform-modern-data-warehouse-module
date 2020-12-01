# Output RG name and ID

output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "rg_id" {
  value = azurerm_resource_group.rg.id
}

# Output data factory principal id

output "data_factory_principal_id" {
  value = azurerm_data_factory.datafactory.identity[0].principal_id
}

# Output Data Lake ID

output "datalake_id" {
  value = azurerm_storage_account.datalake.id
}

# Output check state  Logic app ID

output "checkstate_la_id" {
  value = azurerm_logic_app_workflow.yoda_checkstate_synapse.id
}

# Output scale compute Logic app ID

output "scalecompute_la_id" {
  value = azurerm_logic_app_workflow.yoda_scalecompute_synapse.id
}

# Output pbi refresh dataset Logic app ID

output "pbi_refreshdata_la_id" {
  value = azurerm_logic_app_workflow.yoda_pbi_refreshdata_synapse.id
}

# Output Failure notification Logic app ID

output "failure_la_id" {
  value = azurerm_logic_app_workflow.yodalafailurenotification.id
}

# Output Start/Stop Logic app ID

output "startstop_la_id" {
  value = azurerm_logic_app_workflow.yodalastopstartsynapse.id
}

# Output Start/Stop Logic app ID

output "GetDatasetHistory_la_id" {
  value = azurerm_logic_app_workflow.yodalaGetDatasetHistory.id
}

# Output Log Analytics ID

output "la_workspace_id" {
  value = azurerm_log_analytics_workspace.yodalogs.id
}

# Output DW Function app ID

output "dw_function_id" {
  value = azurerm_function_app.dw_functionapp.id
}

# Output Azure SQL server ID

output "sql_server_id" {
  value = azurerm_sql_server.yodasql.id
}

# Output Azure Key Vault ID

output "key_vault_id" {
  value = azurerm_key_vault.yodakv.id
}

# Output Data Bricks ID (Enable when needed and requirements fully discovered)

#output "databricks_id" {
#  value = azurerm_databricks_workspace.yoda_databricks.id
#}

