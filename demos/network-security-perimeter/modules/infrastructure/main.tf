## Create a virtual network for the resources deployed to this demo
## 
resource "azurerm_virtual_network" "vnet" {
  name                = "vnetnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  address_space = var.address_space_vnet

  # Use the wireserver for DNS resolution
  dns_servers = [
    "168.63.129.16"
  ]
}

## Enable virtual network flow logs
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "flvnet${var.region_code}${var.random_string}"
  network_watcher_name = "NetworkWatcher_${var.region}"
  resource_group_name  = var.resource_group_name_network_watcher

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet.id

  # Enable VNet Flow Logs and use version 2
  enabled = true
  version = 2

  # Send the flow logs to a storage account and retain them for 7 days
  storage_account_id = var.storage_account_vnet_flow_logs
  retention_policy {
    enabled = true
    days    = 7
  }

  # Send the flow logs to Traffic Analytics and send every 10 minutes
  traffic_analytics {
    enabled               = true
    workspace_id          = var.law_workspace_id
    workspace_region      = var.law_region
    workspace_resource_id = var.law_resource_id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

## Create a subnet for the virtual machine
##
resource "azurerm_subnet" "subnet_app" {
  name                 = "snet-app"
  resource_group_name  = var.resource_group_name_workload
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet
  address_prefixes = [cidrsubnet(var.address_space_vnet[0], 2, 1)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create a subnet for the Azure Bastion
##
resource "azurerm_subnet" "subnet_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name_workload
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet  
  address_prefixes = [cidrsubnet(var.address_space_vnet[0], 2, 0)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create a subnet for the Private Endpoints
##
resource "azurerm_subnet" "subnet_svc" {
  name                 = "snet-svc"
  resource_group_name  = var.resource_group_name_workload
  virtual_network_name = azurerm_virtual_network.vnet.name
  # Reserve a /27 for the subnet
  address_prefixes = [cidrsubnet(var.address_space_vnet[0], 2, 2)]
  # Enable Private Endpoint Network Security Group and Routing Policies
  private_endpoint_network_policies = "Enabled"
}

## Create Private DNS Zones and link them to the virtual network for each resource that will be used in the lab
##
resource "azurerm_private_dns_zone" "private_dns_zone" {
  depends_on = [ 
    azurerm_virtual_network.vnet 
  ]

  for_each = { for idx, zone in local.private_dns_zones : zone => zone }

  name                = each.value
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  depends_on = [ 
    azurerm_virtual_network.vnet,
    azurerm_private_dns_zone.private_dns_zone
  ]

  for_each = { for idx, zone in local.private_dns_zones : zone => zone }

  name                  = "${each.value}-link"
  resource_group_name   = var.resource_group_name_workload
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

## Create network security group that will be used on the application subnet
##
resource "azurerm_network_security_group" "nsg_app" {
  name                = "nsappnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags
}

## Associate the network security group with the application subnet
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_app" {
  depends_on = [
    azurerm_subnet.subnet_app,
    azurerm_network_security_group.nsg_app
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = azurerm_network_security_group.nsg_app.id
}

## Create a network security group for the subnet where the Private Endpoints will be deployed to
##
resource "azurerm_network_security_group" "nsg_svc" {
  name                = "nsgsvcnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags
}

## Associate the network security group with the subnet where the Private Endpoints will be deployed to
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    azurerm_network_security_group.nsg_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = azurerm_network_security_group.nsg_svc.id
}

## Create a public IP address to be used by the Azure Bastion instance which will run in the production transit virtual network
##
resource "azurerm_public_ip" "pip_bastion" {
  name                = "pipbstnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "bstprod${var.region_code}${var.random_string}"
}

## Create an Azure Bastion instance in the production transit virtual network
##
resource "azurerm_bastion_host" "bastion" {
  depends_on = [
    azurerm_public_ip.pip_bastion
  ]

  name                = "bstnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.pip_bastion.id
  }

  # Use basic SKU since a single virtual network
  sku = "Basic"

  tags = var.tags
}

## Create a user-assigned managed identity that will be associated to the virtual machine and used
## to authenticate to the resources in this lab
resource "azurerm_user_assigned_identity" "umi" {
  location            = var.region
  name                = "umivmnsp${var.region_code}${var.random_string}"
  resource_group_name = var.resource_group_name_workload

  tags = var.tags
}

## Create a public IP address to be used by the Azure virtual machine to allow access to the Internet
##
resource "azurerm_public_ip" "pip_vm" {
  name                = "pipvmnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  allocation_method   = "Static"
  sku                 = "Standard"
}

## Create the virtual network interface for the virtual machine
##
resource "azurerm_network_interface" "nic" {
  name                = "nicvmnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  # Enable accelerated networking on the network interface
  accelerated_networking_enabled = true

  # Configure the IP settings for the network interface
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_app.address_prefixes[0], 20)
    public_ip_address_id          = azurerm_public_ip.pip_vm.id
  }
  tags = var.tags
}

## Create the virtual machine
##
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "vmnsp${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  admin_username = var.vm_admin_username
  admin_password = var.vm_admin_password

  size = var.vm_sku_size
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.umi.id]
  }

  # Enable boot diagnostics using Microsoft-managed storage account
  #
  boot_diagnostics {
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "osdiskvmwebnsp${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
    caching              = "ReadWrite"
  }

  tags = merge(var.tags, {
    cycle = "true"
  })
}

## Execute the provisioning script via the custom script extension
##
resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_windows_virtual_machine.vm
  ]

  virtual_machine_id = azurerm_windows_virtual_machine.vm.id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version =  "1.10"
  protected_settings = jsonencode(
    {
      "commandToExecute" : "powershell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(file("${path.module}/../../scripts/bootstrap-windows-tool.ps1"), "UTF-16LE")}"
    }
  )

  # Adjust timeout because provisioning script can take a fair amount of time
  timeouts {
    create = "60m"
    update = "60m"
  }

  tags = var.tags
}

