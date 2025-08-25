locals {
  # Configure standard naming convention for relevant resources
  vm_name  = "vm"
  nic_name = "nic"

  # Storage variables
  os_disk_name      = "mdos"
  data_disk_name    = "mddata"

  # Extension variables
  custom_script_extension_version = "1.10"
  monitor_agent_handler_version   = "1.36"

  # Add additional tags
  required_tags = {
    cycle = "true"
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}
