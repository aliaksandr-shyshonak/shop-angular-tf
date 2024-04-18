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

resource "azurerm_windows_function_app_slot" "products_service_function_app_slot" {
  name                       = "wfas-product-service-slot-ne-001"
  function_app_id            = azurerm_windows_function_app.products_service.id
  storage_account_name       = azurerm_storage_account.product_service_account.name
  storage_account_access_key = azurerm_storage_account.product_service_account.primary_access_key

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
}

# App Config
resource "azurerm_app_configuration" "product_service_config" {
  name                = "appconfig-product-service-ne-001"
  resource_group_name = azurerm_resource_group.product_service_rg.name
  location            = azurerm_resource_group.product_service_rg.location
  sku                 = "free"
}

# API Manager
resource "azurerm_resource_group" "api_rg" {
  name     = "rg-api-manager-ne-001"
  location = "northeurope"
}

resource "azurerm_api_management" "api_manager" {
  name                = "apim-api-manager-ne-001"
  resource_group_name = azurerm_resource_group.api_rg.name
  location            = azurerm_resource_group.api_rg.location
  publisher_name      = "Aliaksandr Shyshonak"
  publisher_email     = "aliaksandr_shyshonak@epam.com"

  sku_name = "Consumption_0"
}

resource "azurerm_api_management_api" "product_service_api" {
  name                = "apim-product-service-ne-001"
  resource_group_name = azurerm_resource_group.api_rg.name
  api_management_name = azurerm_api_management.api_manager.name
  revision            = "1"
  display_name        = "Product Service API"
  path                = "product-service"

  protocols = ["https"]
}

data "azurerm_function_app_host_keys" "product_service_keys" {
  name                = azurerm_windows_function_app.products_service.name
  resource_group_name = azurerm_resource_group.product_service_rg.name
}

resource "azurerm_api_management_backend" "product_service_backend" {
  name                = "apimb-product-service-ne-001"
  resource_group_name = azurerm_resource_group.api_rg.name
  api_management_name = azurerm_api_management.api_manager.name
  protocol            = "http"
  url                 = "https://${azurerm_windows_function_app.products_service.name}.azurewebsites.net/api"
  description         = "Product Service API"

  credentials {
    certificate = []
    query       = {}

    header = {
      "x-functions-key" = data.azurerm_function_app_host_keys.product_service_keys.default_function_key
    }
  }
}

resource "azurerm_api_management_api_policy" "product_service_api_policy" {
  api_management_name = azurerm_api_management.api_manager.name
  api_name            = azurerm_api_management_api.product_service_api.name
  resource_group_name = azurerm_resource_group.api_rg.name

  xml_content = <<XML
 <policies>
 	<inbound>
 		<set-backend-service backend-id="${azurerm_api_management_backend.product_service_backend.name}"/>
 		<base/>
 	</inbound>
 	<backend>
 		<base/>
 	</backend>
 	<outbound>
 		<base/>
 	</outbound>
 	<on-error>
 		<base/>
 	</on-error>
 </policies>
XML
}

resource "azurerm_api_management_api_operation" "get_product_list" {
  operation_id        = "get_product_list"
  api_name            = azurerm_api_management_api.product_service_api.name
  api_management_name = azurerm_api_management.api_manager.name
  resource_group_name = azurerm_resource_group.api_rg.name
  display_name        = "Get all products"
  method              = "GET"
  url_template        = "/products"
}

resource "azurerm_api_management_api_operation" "get_product_by_id" {
  operation_id        = "get_product_by_id"
  api_name            = azurerm_api_management_api.product_service_api.name
  api_management_name = azurerm_api_management.api_manager.name
  resource_group_name = azurerm_resource_group.api_rg.name
  display_name        = "Get product by id"
  method              = "GET"
  url_template        = "/products/{id}"

  template_parameter {
    name     = "id"
    type     = "guid"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "post_product" {
  operation_id        = "post_product"
  api_name            = azurerm_api_management_api.product_service_api.name
  api_management_name = azurerm_api_management.api_manager.name
  resource_group_name = azurerm_resource_group.api_rg.name
  display_name        = "Create a new product"
  method              = "POST"
  url_template        = "/products"
}

resource "azurerm_api_management_api_operation" "get_product_total" {
  operation_id        = "get_product_total"
  api_name            = azurerm_api_management_api.product_service_api.name
  api_management_name = azurerm_api_management.api_manager.name
  resource_group_name = azurerm_resource_group.api_rg.name
  display_name        = "Get total of available products"
  method              = "GET"
  url_template        = "/products/total"
}

resource "azurerm_api_management_api_operation" "example" {
  operation_id        = "example"
  api_name            = azurerm_api_management_api.product_service_api.name
  api_management_name = azurerm_api_management.api_manager.name
  resource_group_name = azurerm_resource_group.api_rg.name
  display_name        = "Example"
  method              = "GET"
  url_template        = "/example"
  description         = "Example long <b>description</b>."

  response {
    status_code = 200
  }
}

# Cosmos DB
resource "azurerm_resource_group" "cosmos_db_rg" {
  name     = "rg-cosmos-db-ne-001"
  location = "northeurope"
}

resource "azurerm_cosmosdb_account" "cosmos_db_account" {
  name                = "cdbacc-app-database-ne-001"
  resource_group_name = azurerm_resource_group.cosmos_db_rg.name
  location            = azurerm_resource_group.cosmos_db_rg.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Eventual"
  }

  geo_location {
    failover_priority = 0
    location          = azurerm_resource_group.cosmos_db_rg.location
  }
}

resource "azurerm_cosmosdb_sql_database" "product_database" {
  name                = "product-db"
  resource_group_name = azurerm_resource_group.cosmos_db_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_db_account.name
}

resource "azurerm_cosmosdb_sql_container" "products" {
  name                = "products"
  resource_group_name = azurerm_resource_group.cosmos_db_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_db_account.name
  database_name       = azurerm_cosmosdb_sql_database.product_database.name
  partition_key_path  = "/id"

  # Cosmos DB supports TTL for the records
  default_ttl = -1

  indexing_policy {
    excluded_path {
      path = "/*"
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "stocks" {
  name                = "stocks"
  resource_group_name = azurerm_resource_group.cosmos_db_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_db_account.name
  database_name       = azurerm_cosmosdb_sql_database.product_database.name
  partition_key_path  = "/id"

  # Cosmos DB supports TTL for the records
  default_ttl = -1

  indexing_policy {
    excluded_path {
      path = "/*"
    }
  }
}
