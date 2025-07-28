locals {
  # Configure standard naming convention for relevant resources
  vm_name = "vm"
  nic_name = "nic"

  # Network variables
  ip_configuration_name = "primary"

  # Storage variables
  os_disk_name          = "mdos"
  os_disk_caching       = "ReadWrite"
  data_disk_name        = "mddata"
  data_disk_caching       = "ReadWrite"
  data_disk_lun         = 10

  # Extension variables
  custom_script_extension_version = "2.1"
  automatic_extension_ugprade = true
  monitor_agent_handler_version = "1.21"

  # Add additional tags
  required_tags = {
    cycle = "true"
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}
