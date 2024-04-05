terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.92.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# Frontend
resource "azurerm_resource_group" "front_end_rg" {
  name     = "rg-frontend-sand-ne-001"
  location = "northeurope"
}

resource "azurerm_storage_account" "front_end_storage_account" {
  name                = "staccfrontne001"
  resource_group_name = azurerm_resource_group.front_end_rg.name
  location            = azurerm_resource_group.front_end_rg.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"

  static_website {
    index_document = "index.html"
  }
}

# Product service
resource "azurerm_resource_group" "product_service_rg" {
  name     = "rg-product-service-ne-001"
  location = "northeurope"
}

resource "azurerm_storage_account" "product_service_account" {
  name                     = "staccproductservfane001"
  resource_group_name      = azurerm_resource_group.product_service_rg.name
  location                 = azurerm_resource_group.product_service_rg.location
  account_replication_type = "LRS"
  account_tier             = "Standard"
}

resource "azurerm_storage_share" "product_service_account" {
  name                 = "ss-product-service-ne-001"
  storage_account_name = azurerm_storage_account.product_service_account.name
  quota                = 2
}

resource "azurerm_service_plan" "product_service_plan" {
  name                = "sp-product-service-ne-001"
  resource_group_name = azurerm_resource_group.product_service_rg.name
  location            = azurerm_resource_group.product_service_rg.location
  os_type             = "Windows"
  sku_name            = "Y1"
}

resource "azurerm_application_insights" "products_service_insights" {
  name                = "ai-product-service-ne-001"
  resource_group_name = azurerm_resource_group.product_service_rg.name
  location            = azurerm_resource_group.product_service_rg.location
  application_type    = "web"
}

resource "azurerm_windows_function_app" "products_service" {
  name                = "wfa-product-service-ne-001"
  resource_group_name = azurerm_resource_group.product_service_rg.name
  location            = azurerm_resource_group.product_service_rg.location

  storage_account_name       = azurerm_storage_account.product_service_account.name
  storage_account_access_key = azurerm_storage_account.product_service_account.primary_access_key
  service_plan_id            = azurerm_service_plan.product_service_plan.id

  builtin_logging_enabled = false

  site_config {
    always_on = false

    application_insights_key               = azurerm_application_insights.products_service_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.products_service_insights.connection_string

    # For production systems set this to false, but consumption plan supports only 32bit workers
    use_32_bit_worker = true

    # Enable function invocations from Azure Portal.
    cors {
      allowed_origins = ["https://portal.azure.com", "http://localhost:4200", "https://staccfrontne001.z16.web.core.windows.net"]
    }

    application_stack {
      node_version = "~18"
    }
  }

  app_settings = {
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = azurerm_storage_account.product_service_account.primary_connection_string
    WEBSITE_CONTENTSHARE                     = azurerm_storage_share.product_service_account.name
  }

  # The app settings changes cause downtime on the Function App. e.g. with Azure Function App Slots
  # Therefore it is better to ignore those changes and manage app settings separately off the Terraform.
  lifecycle {
    ignore_changes = [
      app_settings,
      site_config["application_stack"], // workaround for a bug when azure just "kills" your app
      tags["hidden-link: /app-insights-instrumentation-key"],
      tags["hidden-link: /app-insights-resource-id"],
      tags["hidden-link: /app-insights-conn-string"]
    ]
  }
}
