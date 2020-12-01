# Log Analytics Workspace

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "${var.service_short_name}-${var.environment_short_name}-la"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = merge(var.common_tags, var.solution_tags)
}

resource "azurerm_log_analytics_solution" "adfanalytics" {
  solution_name         = "AzureDataFactoryAnalytics"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.logs.id
  workspace_name        = azurerm_log_analytics_workspace.logs.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/AzureDataFactoryAnalytics"
  }
}

# Azure Monitor Action Group

resource "azurerm_monitor_action_group" "actiongroup" {
  name                = "Failure Notifications"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "failures"

  email_receiver {
    name                    = "alertsemail"
    email_address           = var.notificationemailaddress
    use_common_alert_schema = true
  }

  tags = merge(var.common_tags, var.solution_tags)
}

# Data Lake diagnostics

data "azurerm_monitor_diagnostic_categories" "datalakediagnosticcategories" {
  resource_id = azurerm_storage_account.datalake.id
}

resource "azurerm_monitor_diagnostic_setting" "datalakediagnosticsettings" {
  name                       = "Send all to log analytics"
  target_resource_id         = azurerm_storage_account.datalake.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.datalakediagnosticcategories.logs

    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.datalakediagnosticcategories.metrics

    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }
}

# Data Factory monitoring

data "azurerm_monitor_diagnostic_categories" "datafactorydiagnosticcategories" {
  resource_id = azurerm_data_factory.datafactory.id
}

resource "azurerm_monitor_diagnostic_setting" "datafactorydiagnosticsettings" {
  name                           = "Send all to log analytics"
  target_resource_id             = azurerm_data_factory.datafactory.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.logs.id
  log_analytics_destination_type = "Dedicated"

  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.datafactorydiagnosticcategories.logs

    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.datafactorydiagnosticcategories.metrics

    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "failedpipelineruns" {
  name                = "${azurerm_data_factory.datafactory.name}-FailedPipelineRuns"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  action {
    action_group  = ["${azurerm_monitor_action_group.actiongroup.id}"]
    email_subject = "Failed Pipeline Runs on ${azurerm_data_factory.datafactory.name}"
  }

  tags = merge(var.common_tags, var.solution_tags)

  data_source_id = azurerm_log_analytics_workspace.logs.id
  description    = "Alert on DF failed pipeline runs"
  enabled        = true
  # Count all requests with server error result code grouped into 5-minute bins
  query       = <<-QUERY
    let pipelines = ADFPipelineRun 
    | where Status == 'Failed' and Category == "PipelineRuns";
    let activities = ADFActivityRun
    | where Category == "ActivityRuns"
    and Status == "Failed"
    and ActivityType != "ExecutePipeline"
    and ActivityType != "IfCondition"
    and ActivityType != "ForEach" ;
    pipelines
    | join kind = inner 
    activities
    on $left.RunId == $right.PipelineRunId
    |project DataFactory=substring(tostring(split(ResourceId, "/", 8)), 2, strlen(tostring(split(ResourceId, "/", 8)))-4) , TimeGenerated, PipelineName, ActivityName, RunId, Hash=hash_sha256(strcat(PipelineName,Parameters)), Parameters, ErrorMessage, FailureType, Start , End , Status
    |distinct DataFactory , TimeGenerated, PipelineName, ActivityName, RunId, Hash, Parameters, ErrorMessage, FailureType, Start , End , Status
    |order by TimeGenerated desc
  QUERY
  severity    = 1
  frequency   = 15
  time_window = 15
  trigger {
    operator  = "GreaterThan"
    threshold = 0
  }

  lifecycle {
    ignore_changes = [
      query
    ]
  }
}

# Azure Synapse diagnostics

data "azurerm_monitor_diagnostic_categories" "synapsediagnosticcategories" {
  resource_id = azurerm_sql_database.synapsedb.id
}

resource "azurerm_monitor_diagnostic_setting" "synapsediagnosticsettings" {
  name                       = "Send all to log analytics"
  target_resource_id         = azurerm_sql_database.synapsedb.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.synapsediagnosticcategories.logs

    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.synapsediagnosticcategories.metrics

    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }
}

# Staging database diagnostics

data "azurerm_monitor_diagnostic_categories" "sqldiagnosticcategories" {
  resource_id = azurerm_sql_database.dwstagingdb.id
}

resource "azurerm_monitor_diagnostic_setting" "dwstagingdbdiagnosticsettings" {
  name                       = "Send all to log analytics"
  target_resource_id         = azurerm_sql_database.dwstagingdb.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.sqldiagnosticcategories.logs

    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.sqldiagnosticcategories.metrics

    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = false
      }
    }
  }
}