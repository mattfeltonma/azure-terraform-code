## Create transit virtual network
##
resource "azurerm_virtual_network" "vnet_transit" {
  name                = "vnettr${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = merge(var.tags, var.tags_vnet)

  address_space = var.address_space_vnet
  dns_servers   = var.dns_servers
}

## Create the virtual network flow logs and enable traffic analytics for the transit virtual network
##
resource "azurerm_network_watcher_flow_log" "vnet_flow_log" {
  name                 = "fl${azurerm_virtual_network.vnet_transit.name}"
  network_watcher_name = "NetworkWatcher_${var.region}"
  resource_group_name  = var.resource_group_name_network_watcher

  # The target resource is the virtual network
  target_resource_id = azurerm_virtual_network.vnet_transit.id

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

## Create the NSG for the public interface of the firewall deployed to the transit virtual network
## This NSG will block all incoming traffic to the public interface
resource "azurerm_network_security_group" "nsg_transit_fw_pub" {
  name                = "nsgfwpub${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

}

## Create the NSG for the private interface of the firewall deployed to the transit virtual network
## This NSG will allow all RFC1918 traffic to the private interface
resource "azurerm_network_security_group" "nsg_transit_fw_priv" {

  name                = "nsgfwpriv${var.environment}${var.region_code}${var.random_string}"
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

## Create route tables for the GatewaySubnet
##
resource "azurerm_route_table" "rt_gateway" {
  name                = "rtgw${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  bgp_route_propagation_enabled = true
}

## Create route tables for the private and public subnet
##
resource "azurerm_route_table" "rt_public" {
  name                = "rtpub${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  bgp_route_propagation_enabled = false
}

resource "azurerm_route_table" "rt_private" {
  name                = "rtpriv${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  tags                = var.tags

  bgp_route_propagation_enabled = true
}

## Create the subnets for the transit virtual network
##
resource "azurerm_subnet" "subnet_gateway" {
  depends_on = [
    azurerm_network_watcher_flow_log.vnet_flow_log,
    azurerm_virtual_network.vnet_transit
  ]

  name                              = "GatewaySubnet"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.vnet_transit.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 0)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_firewall_public" {
  depends_on = [
    azurerm_subnet.subnet_gateway
  ]

  name                              = "snet-fwpub"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.vnet_transit.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 1)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_firewall_private" {
  depends_on = [
    azurerm_subnet.subnet_firewall_public
  ]

  name                              = "snet-fwpriv"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.vnet_transit.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 2)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_bastion" {
  depends_on = [
    azurerm_subnet.subnet_firewall_private
  ]

  name                              = "AzureBastionSubnet"
  resource_group_name               = var.resource_group_name_workload
  virtual_network_name              = azurerm_virtual_network.vnet_transit.name
  address_prefixes                  = [cidrsubnet(var.address_space_vnet[0], 3, 3)]
  private_endpoint_network_policies = "Enabled"
}

## Associate NSGs to firewall public subnet and private subnet in transit virtual networks
##
resource "azurerm_subnet_network_security_group_association" "nsg_association_firewall_public" {
  depends_on = [
    azurerm_network_security_group.nsg_transit_fw_pub,
    azurerm_subnet.subnet_gateway,
    azurerm_subnet.subnet_firewall_private,
    azurerm_subnet.subnet_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_firewall_public.id
  network_security_group_id = azurerm_network_security_group.nsg_transit_fw_pub.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_firewall_private" {
  depends_on = [
    azurerm_network_security_group.nsg_transit_fw_priv,
    azurerm_subnet.subnet_firewall_private,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_public
  ]

  subnet_id                 = azurerm_subnet.subnet_firewall_private.id
  network_security_group_id = azurerm_network_security_group.nsg_transit_fw_priv.id
}

## Associate route tables with the subnets in the transit virtual networks
##
resource "azurerm_subnet_route_table_association" "rt_association_gateway" {
  depends_on = [
    azurerm_route_table.rt_gateway,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_private
  ]

  subnet_id      = azurerm_subnet.subnet_gateway.id
  route_table_id = azurerm_route_table.rt_gateway.id
}

resource "azurerm_subnet_route_table_association" "rt_association_firewall_public" {
  depends_on = [
    azurerm_route_table.rt_public,
    azurerm_subnet_route_table_association.rt_association_gateway
  ]

  subnet_id      = azurerm_subnet.subnet_firewall_public.id
  route_table_id = azurerm_route_table.rt_public.id
}

resource "azurerm_subnet_route_table_association" "rt_association_firewall_private" {
  depends_on = [
    azurerm_route_table.rt_private,
    azurerm_subnet_network_security_group_association.nsg_association_firewall_public
  ]

  subnet_id      = azurerm_subnet.subnet_firewall_private.id
  route_table_id = azurerm_route_table.rt_private.id
}

## Create public IP addresses for VPN Gateways (2 per region for active/active configuration)
##
resource "azurerm_public_ip" "pip_vpn_gateway" {
  name                = "pipvpn${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "pipvpn${var.environment}${var.region_code}${var.random_string}"

  # As of 10/14/2024 public IPs are deployed as zone redundant by default even if you don't specify zones
  # https://azure.microsoft.com/en-us/blog/azure-public-ips-are-now-zone-redundant-by-default/
}

## Create a VPN Gateway in each region that can be used to create IPSec VPNs to test on-premises connectivity for the demo.
## This is required for this demo in order to set the VNet peering settings properly
resource "azurerm_virtual_network_gateway" "vgw_vpn" {
  depends_on = [
    azurerm_public_ip.pip_vpn_gateway,
    azurerm_subnet_route_table_association.rt_association_firewall_private
  ]

  name                = "vgw${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1"

  active_active = false
  enable_bgp    = true

  ip_configuration {
    name                          = "ipconfig"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_vpn_gateway.id
    subnet_id                     = azurerm_subnet.subnet_gateway.id
  }

  bgp_settings {
    asn = "65515"
    peering_addresses {
      ip_configuration_name = "ipconfig"
    }

  }
  tags = var.tags
}

## Create a public IP address to be used by the Azure Bastion instance which will run in the production transit virtual network
##
resource "azurerm_public_ip" "pip_bastion" {

  count = var.bastion == true ? 1 : 0

  name                = "pipbstprod${var.region_code}${var.random_string}"
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
    azurerm_public_ip.pip_bastion,
    azurerm_virtual_network_gateway.vgw_vpn
  ]

  count = var.bastion == true ? 1 : 0

  name                = "bstprod${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.pip_bastion[0].id
  }

  # Set to Standard SKU because VMs use 2222 as SSH ports
  sku = "Standard"

  tags = var.tags
}

## Create the internal load balancer which will be used by the NVAs for the private subnet containing the trusted NIC in the transit virtual network
##
resource "azurerm_lb" "lb_trusted" {

  name                = "albtrunva${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  sku                 = "Standard"
  sku_tier            = "Regional"

  frontend_ip_configuration {
    name = "lbtrust"
    zones = [
      1,
      2,
      3
    ]

    # Internal networking configuration
    subnet_id                     = azurerm_subnet.subnet_firewall_private.id
    private_ip_address            = cidrhost(azurerm_subnet.subnet_firewall_private.address_prefixes[0], 9)
    private_ip_address_allocation = "Static"
  }
}

## Create the backend pool and probe for private internal load balancer which will be used by trusted NICs of the NVA
##
resource "azurerm_lb_backend_address_pool" "lb_pool_trusted" {
  depends_on = [
    azurerm_lb.lb_trusted
  ]

  name            = "lbpoolbetrusted"
  loadbalancer_id = azurerm_lb.lb_trusted.id
}

resource "azurerm_lb_probe" "lb_probe_trusted" {
  depends_on = [
    azurerm_lb_backend_address_pool.lb_pool_trusted
  ]

  name                = "lbprobetrusted"
  loadbalancer_id     = azurerm_lb.lb_trusted.id
  protocol            = "Tcp"
  port                = 2222
  interval_in_seconds = 5
  number_of_probes    = 2
}

## Create the load balancer rule to send all traffic to the backend pool
##
resource "azurerm_lb_rule" "lb_rule_trusted" {
  depends_on = [azurerm_lb_probe.lb_probe_trusted]

  name                           = "lbrulebetrusted"
  loadbalancer_id                = azurerm_lb.lb_trusted.id
  frontend_ip_configuration_name = "lbtrust"
  backend_address_pool_ids = [
    azurerm_lb_backend_address_pool.lb_pool_trusted.id
  ]
  probe_id                = azurerm_lb_probe.lb_probe_trusted.id
  protocol                = "All"
  frontend_port           = 0
  backend_port            = 0
  floating_ip_enabled     = true
  idle_timeout_in_minutes = 4
  load_distribution       = "Default"
  disable_outbound_snat   = true
}

## Create the public IP address for the public load balancer
##
resource "azurerm_public_ip" "pip_lb_untrusted" {
  name                = "piplbutru${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "lbutrunva${var.environment}${var.region_code}${var.random_string}"
}

## Create the external load balancer which will be used by the NVAs for the public subnet in the transit virtual network
##
resource "azurerm_lb" "lb_untrusted" {

  name                = "albeutrunva${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  sku                 = "Standard"
  sku_tier            = "Regional"

  frontend_ip_configuration {
    name = "lbuntrust"

    # External networking configuration
    public_ip_address_id = azurerm_public_ip.pip_lb_untrusted.id
  }
}

## Create the backend pool and probe for public external load balancer which will be used by untrusted NICs of the NVA
##
resource "azurerm_lb_backend_address_pool" "lb_pool_untrusted" {
  depends_on = [
    azurerm_lb.lb_untrusted
  ]

  name            = "lbpooluntrusted"
  loadbalancer_id = azurerm_lb.lb_untrusted.id
}

resource "azurerm_lb_probe" "lb_probe_untrusted" {
  depends_on = [
    azurerm_lb_backend_address_pool.lb_pool_untrusted
  ]

  name                = "lbprobeuntrusted"
  loadbalancer_id     = azurerm_lb.lb_untrusted.id
  protocol            = "Tcp"
  port                = 2222
  interval_in_seconds = 5
  number_of_probes    = 2
}

## Create the public IP addresses for the NVA
##
resource "azurerm_public_ip" "pip_vm_nva" {
  name                = "pipnva0${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = "vmnva0${var.environment}${var.region_code}${var.random_string}"
}

## Create NVA NIC for untrusted interface
##
resource "azurerm_network_interface" "nic_nva_untrusted" {
  depends_on = [
    azurerm_subnet_route_table_association.rt_association_firewall_public,
    azurerm_public_ip.pip_vm_nva
  ]

  name                = "nicunnva${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  # Low end SKUs like D2s_v3 only support one NIC with accelerated networking so disable for the untrusted NIC
  accelerated_networking_enabled = false

  # Configure IP forwarding since this will be routing traffic between spokes
  ip_forwarding_enabled = true

  # Configure static allocation of IP address and grab 20th IP in subnet
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_firewall_public.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_firewall_public.address_prefixes[0], 20)
    public_ip_address_id          = azurerm_public_ip.pip_vm_nva.id
  }
  tags = var.tags
}

## Associate untrusted NIC with untrusted backend pool
##
resource "azurerm_network_interface_backend_address_pool_association" "lb_pool_assoc_be_untrusted_nva" {
  depends_on = [
    azurerm_network_interface.nic_nva_untrusted
  ]

  network_interface_id    = azurerm_network_interface.nic_nva_untrusted.id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_pool_untrusted.id
}

## Create trusted NIC for NVA
##
resource "azurerm_network_interface" "nic_nva_trusted" {
  depends_on = [
    azurerm_subnet_route_table_association.rt_association_firewall_private,
    azurerm_network_interface_backend_address_pool_association.lb_pool_assoc_be_untrusted_nva
  ]

  name                           = "nictrnva${var.environment}${var.region_code}${var.random_string}"
  location                       = var.region
  resource_group_name            = var.resource_group_name_workload
  accelerated_networking_enabled = true

  # Configure IP forwarding since this will be routing traffic between spokes
  ip_forwarding_enabled = true

  # Configure static allocation of IP address and grab 20th IP in subnet
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet_firewall_private.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(azurerm_subnet.subnet_firewall_private.address_prefixes[0], 20)
  }
  tags = var.tags
}

## Associate trusted NIC with trusted backend pool
##
resource "azurerm_network_interface_backend_address_pool_association" "private-nic-pool" {
  depends_on = [
    azurerm_network_interface.nic_nva_trusted
  ]

  network_interface_id    = azurerm_network_interface.nic_nva_trusted.id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_pool_trusted.id
}

## Create NVA virtual machines
##
resource "azurerm_linux_virtual_machine" "vm" {

  name                = "vmnva${var.environment}${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = var.resource_group_name_workload

  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  size = var.vm_sku_size
  network_interface_ids = [
    azurerm_network_interface.nic_nva_trusted.id,
    azurerm_network_interface.nic_nva_untrusted.id
  ]

  # Enable boot diagnostics using Microsoft-managed storage account
  #
  boot_diagnostics {
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "osdiskvmnva${var.environment}${var.region_code}${var.random_string}"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 60
    caching              = "ReadWrite"
  }

  tags = merge(var.tags, {
    cycle = "true"
  })
}

## Use the custom script extension to bootstrap the Ubuntu machine to replicate
## basic NVA functionality
resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_linux_virtual_machine.vm
  ]

  virtual_machine_id = azurerm_linux_virtual_machine.vm.id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({
    commandToExecute = <<-EOT
      /bin/bash -c "echo '${replace(base64encode(file("${path.module}/../../scripts/bootstrap-ubuntu-nva.sh")), "'", "'\\''")}' | base64 -d > /tmp/bootstrap-ubuntu-nva.sh && \
      chmod +x /tmp/bootstrap-ubuntu-nva.sh && \
      /bin/bash /tmp/bootstrap-ubuntu-nva.sh \
      --hostname '${azurerm_linux_virtual_machine.vm.name}' \
      --router_asn '${var.nva_asn}' \
      --nva_private_ip '${azurerm_network_interface.nic_nva_trusted.ip_configuration[0].private_ip_address}' \
      --public_nic_gateway_ip '${cidrhost(azurerm_subnet.subnet_firewall_public.address_prefixes[0], 1)}' \
      --private_nic_gateway_ip '${cidrhost(azurerm_subnet.subnet_firewall_private.address_prefixes[0], 1)}'"
    EOT
  })

  tags = var.tags
}
