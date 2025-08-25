## Create a public IP address for the virtual machine if the public_ip_address_enable variable is set to true
##
module "public_ip_vm" {
  count = var.public_ip_address_enable ? 1 : 0

  source              = "../../public-ip"
  random_string       = var.random_string
  location            = var.location
  location_code       = var.location_code
  resource_group_name = var.resource_group_name

  purpose         = var.purpose
  law_resource_id = var.log_analytics_workspace_id

  tags = var.tags
}

## Create the virtual network interface for the virtual machine
##
resource "azurerm_network_interface" "nic" {
  name                = "${local.nic_name}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Enable accelerated networking on the network interface
  accelerated_networking_enabled = true

  # Configure the IP settings for the network interface
  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address_allocation
    private_ip_address            = var.private_ip_address
    # Configure a public IP on the NIC only if the public_ip_address_enable variable is set to true
    public_ip_address_id          = var.public_ip_address_enable ? module.public_ip_vm[0].id : null
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create the virtual machine
##
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "${local.vm_name}${var.purpose}${var.location_code}${var.random_string}"
  location            = var.location
  resource_group_name = var.resource_group_name

  admin_username = var.admin_username
  admin_password = var.admin_password

  size = var.vm_size
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]
  zone = var.availability_zone

  identity {
    # Configure a system-assigned managed identity if var.identities is not set. If it is, assigned the user-assigned managed identities
    # to the virtual machine
    type = var.identities != null ? var.identities.type : "SystemAssigned"
    identity_ids = var.identities != null ? var.identities.identity_ids : null
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "${local.os_disk_name}${local.vm_name}${var.purpose}${var.location_code}${var.random_string}"
    storage_account_type = var.disk_os_storage_account_type
    disk_size_gb         = var.disk_os_size_gb
    caching              = "ReadWrite"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create a managed disk to use for the data disk
##
resource "azurerm_managed_disk" "data" {
  name                 = "${local.data_disk_name}${local.vm_name}${var.purpose}${var.location_code}${var.random_string}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = var.disk_data_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = var.disk_data_size_gb

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Attach the data disk to the virtual machine
##
resource "azurerm_virtual_machine_data_disk_attachment" "data-attach" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_windows_virtual_machine.vm.id
  lun                = 10
  caching            = "ReadWrite"
}

## Execute the provisioning script via the custom script extension
##
resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_windows_virtual_machine.vm,
    azurerm_virtual_machine_data_disk_attachment.data-attach
  ]

  virtual_machine_id = azurerm_windows_virtual_machine.vm.id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = local.custom_script_extension_version
  protected_settings = jsonencode(
    {
      "commandToExecute" : "powershell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(file("${path.module}/../../../scripts/bootstrap-windows-tool.ps1"), "UTF-16LE")}"
    }
  )

  # Adjust timeout because provisioning script can take a fair amount of time
  timeouts {
    create = "60m"
    update = "60m"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

resource "azurerm_virtual_machine_extension" "ama" {
  depends_on = [
    azurerm_windows_virtual_machine.vm,
    azurerm_virtual_machine_extension.custom-script-extension
  ]

  virtual_machine_id = azurerm_windows_virtual_machine.vm.id

  name                       = "AzureMonitorWindowsAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = local.monitor_agent_handler_version
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}
 
resource "azurerm_monitor_data_collection_rule_association" "dce_win_tools" {
  depends_on = [
    azurerm_virtual_machine_extension.ama
  ]
  name                        = "configurationAccessEndpoint"
  description                 = "Data Collection Endpoint Association for Windows Tools VM"
  data_collection_endpoint_id = var.dce_id
  target_resource_id          = azurerm_windows_virtual_machine.vm.id
}
 
resource "azurerm_monitor_data_collection_rule_association" "dcr_win_tools" {
  depends_on = [
    azurerm_monitor_data_collection_rule_association.dce_win_tools
  ]
  name                    = "dcr${local.vm_name}${var.purpose}${var.location_code}${var.random_string}"
  description             = "Data Collection Rule Association for Windows Tools VM"
  data_collection_rule_id = var.dcr_id
  target_resource_id      = azurerm_windows_virtual_machine.vm.id
}
