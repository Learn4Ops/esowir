resource "azurerm_resource_group" "aks" {
  name     = "aks-resource-group"
  location = "West Europe"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cluster"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.2.0.10"
    service_cidr   = "10.2.0.0/16"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

}

resource "azurerm_user_assigned_identity" "aks" {
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  name                = "aks-managed-identity"
}

resource "azurerm_federated_identity_credential" "testapp-credential" {
  resource_group_name = azurerm_resource_group.aks.name
  parent_id           = azurerm_user_assigned_identity.aks.id
  name                = "aks-federated-credential"
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:testapp:external-secret-service-account"
}

resource "random_string" "kvname" {
  length = 3
  special          = false
  upper = false
}

data "azuread_client_config" "current" {}

resource "azurerm_key_vault" "aks-kv" {
  name                        = "external-secrets-kv-${random_string.kvname.result}"
  location                    = azurerm_resource_group.aks.location
  resource_group_name         = azurerm_resource_group.aks.name
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = false

  access_policy {
    tenant_id = var.tenant_id
    object_id = azurerm_user_assigned_identity.aks.principal_id

    secret_permissions = [
      "Get",
    ]
  }

  access_policy {
    tenant_id = var.tenant_id
    object_id = data.azuread_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Set",
      "List"
    ]
  }
}

resource "azurerm_key_vault_secret" "test-password" {
  name         = "test-password"
  value        = "password123"
  key_vault_id = azurerm_key_vault.aks-kv.id
}

resource "azurerm_key_vault_secret" "test-username" {
  name         = "test-username"
  value        = "testuser"
  key_vault_id = azurerm_key_vault.aks-kv.id
}

output "key_vault_name" {
  value = azurerm_key_vault.aks-kv.name
}