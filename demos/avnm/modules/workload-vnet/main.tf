## Create workload virtual network
##
resource "azurerm_virtual_network" "workload_vnet" {
  name                = "vnet${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = merge(var.tags, var.tags_vnet)

  address_space = var.address_space_vnet
  dns_servers   = var.dns_servers
}

## Create the virtual network flow logs and enable traffic analytics for the transit virtual network
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "fl${azurerm_virtual_network.workload_vnet.name}"
  network_watcher_name = "NetworkWatcher_${var.region}"
  resource_group_name  = var.resource_group_name_network_watcher

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.workload_vnet.id

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

## Create the NSG for the app subnet
## This NSG will allow all RFC1918 traffic
resource "azurerm_network_security_group" "nsg_app" {
  name                = "nsgapp${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  security_rule {
    name                   = "AllowAllInbound"
    description            = "Allow all inbound traffic from RFC1918"
    priority               = 1000
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "*"
    source_port_range      = "*"
    destination_port_range = "*"
    source_address_prefixes = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ]
    destination_address_prefix = "*"
  }

}

## Create the NSG for the app subnet
## This NSG will allow all RFC1918 traffic
resource "azurerm_network_security_group" "nsg_data" {
  name                = "nsgdata${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  security_rule {
    name                   = "AllowAllInbound"
    description            = "Allow all inbound traffic from RFC1918"
    priority               = 1000
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "*"
    source_port_range      = "*"
    destination_port_range = "*"
    source_address_prefixes = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ]
    destination_address_prefix = "*"
  }

}

## Create the NSG for the svc subnet
## This NSG will allow all RFC1918 traffic
resource "azurerm_network_security_group" "nsg_svc" {
  name                = "nsgsvc${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  security_rule {
    name                   = "AllowAllInbound"
    description            = "Allow all inbound traffic from RFC1918"
    priority               = 1000
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "*"
    source_port_range      = "*"
    destination_port_range = "*"
    source_address_prefixes = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ]
    destination_address_prefix = "*"
  }

}

## Create a route table for the app subnet
##
resource "azurerm_route_table" "rt_app" {
  name                = "rtapp${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  bgp_route_propagation_enabled = false
}

## Create a route table for the data subnet
##
resource "azurerm_route_table" "rt_data" {
  name                = "rtdata${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  bgp_route_propagation_enabled = false
}

## Create the subnets for the workload virtual network
##
resource "azurerm_subnet" "subnet_app" {
  depends_on = [ 
    azurerm_virtual_network.workload_vnet 
  ]

  name                              = "snt-app"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.workload_vnet.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 0)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_data" {
  depends_on = [ 
    azurerm_virtual_network.workload_vnet 
  ]

  name                              = "snt-data"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.workload_vnet.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 1)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_svc" {
  depends_on = [ 
    azurerm_virtual_network.workload_vnet 
  ]

  name                              = "snt-svc"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.workload_vnet.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 2)]
  private_endpoint_network_policies = "Enabled"
}

## Associate NSG to the subnets
##
resource "azurerm_subnet_network_security_group_association" "nsg_association_app" {
  depends_on = [
    azurerm_network_security_group.nsg_app,
    azurerm_subnet.subnet_app
  ]

  subnet_id                 = azurerm_subnet.subnet_app.id
  network_security_group_id = azurerm_network_security_group.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_data" {
  depends_on = [
    azurerm_subnet_network_security_group_association.nsg_association_app,
    azurerm_network_security_group.nsg_data,
    azurerm_subnet.subnet_data
  ]

  subnet_id                 = azurerm_subnet.subnet_data.id
  network_security_group_id = azurerm_network_security_group.nsg_data.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_svc" {
  depends_on = [
    azurerm_subnet_network_security_group_association.nsg_association_data,
    azurerm_network_security_group.nsg_svc,
    azurerm_subnet.subnet_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = azurerm_network_security_group.nsg_svc.id
}

## Associate route tables to subnets
##
resource "azurerm_subnet_route_table_association" "route_table_association_app" {
  depends_on = [
    azurerm_subnet_network_security_group_association.nsg_association_svc,
    azurerm_subnet.subnet_app,
    azurerm_route_table.rt_app
  ]

  subnet_id      = azurerm_subnet.subnet_app.id
  route_table_id = azurerm_route_table.rt_app.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_data" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_app,
    azurerm_subnet.subnet_data,
    azurerm_route_table.rt_data
  ]

  subnet_id      = azurerm_subnet.subnet_data.id
  route_table_id = azurerm_route_table.rt_data.id
}

## Create a NIC for the web server
##
resource "azurerm_network_interface" "nic_web_server" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_app
  ]

  name                           = "nicweb${var.environment}${var.region_code}${var.random_string}"
  location                       = var.region
  resource_group_name            = var.resource_group_name_workload
  accelerated_networking_enabled = true

  # Configure static allocation of IP address and grab 20th IP in subnet
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_app.address_prefixes[0], 20)
  }
  tags = var.tags
}

## Create Linux app server which will be setup with Apache and MySQL
##
resource "azurerm_linux_virtual_machine" "vm_web_server" {

  name                = "vmweb${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  size = var.vm_sku_size
  network_interface_ids = [
    azurerm_network_interface.nic_web_server.id
  ]

  boot_diagnostics {
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "osdiskvmweb${var.environment}${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 60
    caching              = "ReadWrite"
  }

  tags = merge(var.tags, {
    cycle = "true"
  })
}

## Use the custom script extension to bootstrap the Ubuntu machine to replicate
## basic app server functionality. Sets SSH port to 2222
resource "azurerm_virtual_machine_extension" "custom_script_extension_web_server" {
  depends_on = [
    azurerm_linux_virtual_machine.vm_web_server
  ]

  virtual_machine_id = azurerm_linux_virtual_machine.vm_web_server.id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({
    commandToExecute = <<-EOT
      /bin/bash -c "echo '${replace(base64encode(file("${path.module}/../../scripts/bootstrap-ubuntu-app.sh")), "'", "'\\''")}' | base64 -d > /tmp/bootstrap-ubuntu-app.sh && \
      chmod +x /tmp/bootstrap-ubuntu-app.sh && \
      /bin/bash /tmp/bootstrap-ubuntu-app.sh true"
    EOT
  })
  tags = var.tags
}

## Create a NIC for the db server
##
resource "azurerm_network_interface" "nic_db_server" {
  depends_on = [
    azurerm_subnet_route_table_association.route_table_association_app
  ]

  count = var.db_vm ? 1 : 0

  name                           = "nicdb${var.environment}${var.region_code}${var.random_string}"
  location                       = var.region
  resource_group_name            = var.resource_group_name_workload
  accelerated_networking_enabled = true

  # Configure static allocation of IP address and grab 20th IP in subnet
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_data.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_data.address_prefixes[0], 20)
  }
  tags = var.tags
}

## Create Linux db server which will be setup with Apache and MySQL
##
resource "azurerm_linux_virtual_machine" "vm_db_server" {
  count = var.db_vm ? 1 : 0

  name                = "vmdb${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  size = var.vm_sku_size
  network_interface_ids = [
    azurerm_network_interface.nic_db_server[0].id
  ]

  boot_diagnostics {
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "osdiskvmdb${var.environment}${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 60
    caching              = "ReadWrite"
  }

  tags = merge(var.tags, {
    cycle = "true"
  })
}

## Use the custom script extension to bootstrap the Ubuntu machine to replicate
## basic app server functionality. Sets SSH port to 2222
resource "azurerm_virtual_machine_extension" "custom_script_extension_db_server" {
  depends_on = [
    azurerm_linux_virtual_machine.vm_db_server
  ]
  count = var.db_vm ? 1 : 0

  virtual_machine_id = azurerm_linux_virtual_machine.vm_db_server[0].id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({
    commandToExecute = <<-EOT
      /bin/bash -c "echo '${replace(base64encode(file("${path.module}/../../scripts/bootstrap-ubuntu-app.sh")), "'", "'\\''")}' | base64 -d > /tmp/bootstrap-ubuntu-app.sh && \
      chmod +x /tmp/bootstrap-ubuntu-app.sh && \
      /bin/bash /tmp/bootstrap-ubuntu-app.sh true"
    EOT
  })
  tags = var.tags
}
