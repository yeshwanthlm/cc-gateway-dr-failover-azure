terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# Common tags for all resources
locals {
  common_tags = {
    Environment = "demo"
    Project     = "confluent-gateway"
    owner_email = var.owner_email
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.azure_location

  tags = local.common_tags
}

# Virtual Network for AKS
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# Subnet for AKS nodes
resource "azurerm_subnet" "aks" {
  name                 = "${var.cluster_name}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group for AKS subnet
resource "azurerm_network_security_group" "aks" {
  name                = "${var.cluster_name}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-kafka"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9092-9099"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = var.vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
    zones          = var.availability_zones

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  tags = local.common_tags
}

# Role assignment for AKS to manage network resources
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# Azure Private DNS Zone for Gateway
resource "azurerm_private_dns_zone" "gateway" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "gateway" {
  name                  = "${var.cluster_name}-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.gateway.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false

  tags = local.common_tags
}

# Private DNS A Record for Gateway
# Note: The IP will be empty initially and updated after LoadBalancer is created
# Azure Load Balancer uses IP addresses, not hostnames, so we use an A record instead of CNAME
resource "azurerm_private_dns_a_record" "gateway" {
  name                = var.gateway_dns_record_name
  zone_name           = azurerm_private_dns_zone.gateway.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = var.gateway_lb_ip != "" ? [var.gateway_lb_ip] : []

  tags = local.common_tags

  lifecycle {
    ignore_changes = [records]
  }
}
