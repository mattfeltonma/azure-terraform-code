########## These resources are always created and are part of a baseline deployment
##########

## Create resource group
##
resource "azurerm_resource_group" "rgwork" {

  name     = "rgaks${var.region_code}${var.random_string}"
  location = var.region

  tags = var.tags
}

## Create a Log Analytics Workspace
##
resource "azurerm_log_analytics_workspace" "law" {
  name                = "lawaks${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

## Create virtual network
##
resource "azurerm_virtual_network" "vnet" {
  name                = "vnetaks${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name
  tags                = var.tags

  address_space = [
    var.address_space_vnet
  ]
  dns_servers = var.dns_servers
}

## Create subnets for the virtual network
##
resource "azurerm_subnet" "subnet_agw" {

  name                 = "snet-agw"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 0)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_aks_sys_node" {

  name                 = "snet-aks-sys-nodes"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 1)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_aks_user_node" {

  name                 = "snet-aks-user-nodes"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 2)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_aks_pod" {

  name                 = "snet-aks-pods"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 3)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_aks_cluster" {

  name                 = "snet-aks-cluster"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 4)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_svc" {

  name                 = "snet-svc"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 5)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_bastion" {

  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 6)
  ]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "subnet_vm" {

  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rgwork.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    cidrsubnet(var.address_space_vnet, 3, 7)
  ]
  private_endpoint_network_policies = "Enabled"
}

## Create route tables
##
resource "azurerm_route_table" "rt_agw" {
  name                = "rtagw${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = var.region

  dynamic "route" {
    for_each = var.standalone == false ? [
      {
        name                   = "udr-default"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      },
      {
        name                   = "udr-rfc1918-1"
        address_prefix         = "10.0.0.0/8"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      },
      {
        name                   = "udr-rfc1918-2"
        address_prefix         = "172.16.0.0/12"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      },
      {
        name                   = "udr-rfc1918-3"
        address_prefix         = "192.168.0.0/16"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      }
    ] : []

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }

  tags = var.tags
}

resource "azurerm_route_table" "rt_aks_sys_node" {
  name                = "rtsysnode${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = var.region

  dynamic "route" {
    for_each = var.standalone == false ? [
      {
        name                   = "udr-default"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      }
    ] : []

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }

  tags = var.tags
}

resource "azurerm_route_table" "rt_aks_user_node" {
  name                = "rtusernode${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = var.region

  dynamic "route" {
    for_each = var.standalone == false ? [
      {
        name                   = "udr-default"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      }
    ] : []

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }
  tags = var.tags
}

resource "azurerm_route_table" "rt_aks_pod" {
  name                = "rtakspod${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = var.region

  dynamic "route" {
    for_each = var.standalone == false ? [
      {
        name                   = "udr-default"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = var.fw_private_ip
      }
    ] : []

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }

  tags = var.tags
}

resource "azurerm_route_table" "rt_vm" {
  name                = "rtvm${var.region_code}${var.random_string}"
  resource_group_name = azurerm_resource_group.rgwork.name
  location            = var.region
  tags                = var.tags
}

## Create Network Security Groups
##
resource "azurerm_network_security_group" "nsg_agw" {
  name                = "nsgagw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  security_rule {
    name                       = "AllowHttpInboundFromInternet"
    description                = "Allow inbound HTTP to Application Gateway Internet"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 80
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHttpsInboundFromInternet"
    description                = "Allow inbound HTTPS to Application Gateway Internet"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                    = "AllowHttpHttpsInboundFromIntranet"
    description             = "Allow inbound HTTP/HTTPS to Application Gateway from Intranet"
    priority                = 1020
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_ranges = [80, 443]
    source_address_prefixes = [
      "192.168.0.0/16",
      "172.16.0.0/12",
      "10.0.0.0/8"
    ]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    description                = "Allow inbound Application Gateway Manager Traffic"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    description                = "Allow inbound traffic from Azure Load Balancer to support probes"
    priority                   = 1040
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    description                = "Deny all inbound traffic"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg_aks_sys_node" {
  name                = "nsgakssysnode${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_aks_user_node" {
  name                = "nsgaksusernode${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_aks_pod" {
  name                = "nsgakspod${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_aks_cluster" {
  name                = "nsgakscluster${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_svc" {
  name                = "nsgsvc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_bastion" {
  name                = "nsgsvc${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  security_rule {
    name                       = "AllowHttpsInbound"
    description                = "Allow inbound HTTPS to allow for connections to Bastion"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    description                = "Allow inbound HTTPS to allow for managemen of Bastion instances"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    description                = "Allow inbound HTTPS to allow Azure Load Balancer health probes"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionHostCommunication"
    description                = "Allow data plane communication between Bastion hosts"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    description                = "Deny all inbound traffic"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSshRdpOutbound"
    description                = "Allow Bastion hosts to SSH and RDP to virtual machines"
    priority                   = 1100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [22, 2222, 3389, 3390]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    description                = "Allow Bastion to connect to dependent services in Azure"
    priority                   = 1110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 443
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowBastionCommunication"
    description                = "Allow data plane communication between Bastion hosts"
    priority                   = 1120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = [8080, 5701]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowHttpOutbound"
    description                = "Allow Bastion to connect to dependent services on the Internet"
    priority                   = 1130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = 80
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "DenyAllOutbound"
    description                = "Deny all outbound traffic"
    priority                   = 2100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "nsg_vm" {
  name                = "nsgvm${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

## Peer the virtual network with the hub virtual network. This is only performed for hub and spoke deployments
##
resource "azurerm_virtual_network_peering" "vnet_peering_to_hub" {
  count = var.standalone == false ? 1 : 0

  name                         = "peer-vnetaks${var.region_code}${var.random_string}-to-hub"
  resource_group_name          = azurerm_resource_group.rgwork.name
  virtual_network_name         = azurerm_virtual_network.vnet.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_to_spoke" {
  depends_on = [
    azurerm_virtual_network_peering.vnet_peering_to_hub
  ]

  count = var.standalone == false ? 1 : 0

  name                         = "peer-hub-to-vnetaks${var.region_code}${var.random_string}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_name
  remote_virtual_network_id    = azurerm_virtual_network.vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

## Associate route tables with subnets
##
resource "azurerm_subnet_route_table_association" "route_table_association_agw" {
  depends_on = [
    azurerm_subnet.subnet_agw,
    azurerm_route_table.rt_agw,
    azurerm_virtual_network_peering.vnet_peering_to_hub[0],
    azurerm_virtual_network_peering.vnet_peering_to_spoke[0]
  ]

  subnet_id      = azurerm_subnet.subnet_agw.id
  route_table_id = azurerm_route_table.rt_agw.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_aks_sys_node" {
  depends_on = [
    azurerm_subnet.subnet_aks_sys_node,
    azurerm_route_table.rt_agw,
    azurerm_virtual_network_peering.vnet_peering_to_hub[0],
    azurerm_virtual_network_peering.vnet_peering_to_spoke[0],
    azurerm_subnet_route_table_association.route_table_association_agw
  ]

  subnet_id      = azurerm_subnet.subnet_aks_sys_node.id
  route_table_id = azurerm_route_table.rt_aks_sys_node.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_aks_user_node" {
  depends_on = [
    azurerm_subnet.subnet_aks_user_node,
    azurerm_route_table.rt_aks_user_node,
    azurerm_virtual_network_peering.vnet_peering_to_hub[0],
    azurerm_virtual_network_peering.vnet_peering_to_spoke[0],
    azurerm_subnet_route_table_association.route_table_association_aks_sys_node
  ]

  subnet_id      = azurerm_subnet.subnet_aks_user_node.id
  route_table_id = azurerm_route_table.rt_aks_user_node.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_aks_pod" {
  depends_on = [
    azurerm_subnet.subnet_aks_pod,
    azurerm_route_table.rt_aks_pod,
    azurerm_virtual_network_peering.vnet_peering_to_hub[0],
    azurerm_virtual_network_peering.vnet_peering_to_spoke[0],
    azurerm_subnet_route_table_association.route_table_association_aks_user_node
  ]

  subnet_id      = azurerm_subnet.subnet_aks_pod.id
  route_table_id = azurerm_route_table.rt_aks_pod.id
}

resource "azurerm_subnet_route_table_association" "route_table_association_vm" {
  depends_on = [
    azurerm_subnet.subnet_vm,
    azurerm_route_table.rt_vm,
    azurerm_virtual_network_peering.vnet_peering_to_hub[0],
    azurerm_virtual_network_peering.vnet_peering_to_spoke[0],
    azurerm_subnet_route_table_association.route_table_association_aks_pod
  ]

  subnet_id      = azurerm_subnet.subnet_vm.id
  route_table_id = azurerm_route_table.rt_vm.id
}

## Associate network security groups
##
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_agw" {
  depends_on = [
    azurerm_subnet.subnet_agw,
    azurerm_network_security_group.nsg_agw,
    azurerm_subnet_route_table_association.route_table_association_vm
  ]

  subnet_id                 = azurerm_subnet.subnet_agw.id
  network_security_group_id = azurerm_network_security_group.nsg_agw.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_aks_sys_node" {
  depends_on = [
    azurerm_subnet.subnet_aks_sys_node,
    azurerm_network_security_group.nsg_aks_sys_node,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_agw
  ]

  subnet_id                 = azurerm_subnet.subnet_aks_sys_node.id
  network_security_group_id = azurerm_network_security_group.nsg_aks_sys_node.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_aks_user_node" {
  depends_on = [
    azurerm_subnet.subnet_aks_user_node,
    azurerm_network_security_group.nsg_aks_user_node,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_aks_sys_node
  ]

  subnet_id                 = azurerm_subnet.subnet_aks_user_node.id
  network_security_group_id = azurerm_network_security_group.nsg_aks_user_node.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_aks_pod" {
  depends_on = [
    azurerm_subnet.subnet_aks_pod,
    azurerm_network_security_group.nsg_aks_pod,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_aks_user_node
  ]

  subnet_id                 = azurerm_subnet.subnet_aks_pod.id
  network_security_group_id = azurerm_network_security_group.nsg_aks_pod.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_aks_cluster" {
  depends_on = [
    azurerm_subnet.subnet_aks_cluster,
    azurerm_network_security_group.nsg_aks_cluster,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_aks_pod
  ]

  subnet_id                 = azurerm_subnet.subnet_aks_cluster.id
  network_security_group_id = azurerm_network_security_group.nsg_aks_cluster.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_svc" {
  depends_on = [
    azurerm_subnet.subnet_svc,
    azurerm_network_security_group.nsg_svc,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_aks_cluster
  ]

  subnet_id                 = azurerm_subnet.subnet_svc.id
  network_security_group_id = azurerm_network_security_group.nsg_svc.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_bastion" {
  depends_on = [
    azurerm_subnet.subnet_bastion,
    azurerm_network_security_group.nsg_bastion,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_svc
  ]

  subnet_id                 = azurerm_subnet.subnet_bastion.id
  network_security_group_id = azurerm_network_security_group.nsg_bastion.id
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association_vm" {
  depends_on = [
    azurerm_subnet.subnet_vm,
    azurerm_network_security_group.nsg_vm,
    azurerm_subnet_network_security_group_association.subnet_nsg_association_bastion
  ]

  subnet_id                 = azurerm_subnet.subnet_vm.id
  network_security_group_id = azurerm_network_security_group.nsg_vm.id
}

########## These resources are only created for standalone deployments
##########

## Create a public IP for the NAT Gateway
##
resource "azurerm_public_ip" "pip_natgw" {

  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_vm
  ]

  count = var.standalone == true ? 1 : 0

  name                = "pipngw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

## Create a NAT Gateway
##
resource "azurerm_nat_gateway" "natgw" {

  depends_on = [
    azurerm_public_ip.pip_natgw
  ]

  count = var.standalone == true ? 1 : 0

  name                = "natgw${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name
  sku_name            = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "natgw_pip_assoc" {
  depends_on = [
    azurerm_nat_gateway.natgw,
    azurerm_public_ip.pip_natgw
  ]

  count = var.standalone == true ? 1 : 0

  nat_gateway_id    = azurerm_nat_gateway.natgw[0].id
  public_ip_address_id = azurerm_public_ip.pip_natgw[0].id
}

## Associate the NAT Gateway to the VM subnet
##
resource "azurerm_subnet_nat_gateway_association" "natgw_assoc" {
  depends_on = [
    azurerm_nat_gateway_public_ip_association.natgw_pip_assoc
  ]

  count = var.standalone == true ? 1 : 0

  subnet_id      = azurerm_subnet.subnet_vm.id
  nat_gateway_id = azurerm_nat_gateway.natgw[0].id
}

## Create Public IP for Azure Bastion and Azure Bastion instance
##
resource "azurerm_public_ip" "pip_bastion" {

  depends_on = [
    azurerm_subnet_network_security_group_association.subnet_nsg_association_vm
  ]

  count = var.standalone == true ? 1 : 0

  name                = "pipbst${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  depends_on = [
    azurerm_public_ip.pip_bastion
  ]

  count = var.standalone == true ? 1 : 0

  name                = "bst${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  ip_configuration {
    name                 = "config"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.pip_bastion[0].id
  }

  sku  = "Basic"
  tags = var.tags
}

## Retrieve SSH public key from Azure SSH Key resource
##
data "external" "ssh_public_key" {
  program = ["bash", "-c", "az sshkey show --name ${var.ssh_key_name} --resource-group ${var.ssh_key_resource_group} --query '{public_key: publicKey}' --output json"]
}

## Create Linux virtual machine
##
resource "azurerm_network_interface" "nic" {
  depends_on = [
    azurerm_subnet_nat_gateway_association.natgw_assoc
  ]

  count = var.standalone == true ? 1 : 0

  name                           = "nicvm${var.region_code}${var.random_string}"
  location                       = var.region
  resource_group_name            = azurerm_resource_group.rgwork.name
  accelerated_networking_enabled = true
  ip_configuration {
    name                          = "ipconfigmain"
    subnet_id                     = azurerm_subnet.subnet_vm.id
    private_ip_address_allocation = "Dynamic"
  }
  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "vm" {
  depends_on = [
    azurerm_network_interface.nic
  ]

  count = var.standalone == true ? 1 : 0

  name                = "vmaks${var.region_code}${var.random_string}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rgwork.name

  admin_username                  = "localadmin"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  size = var.vm_sku
  network_interface_ids = [
    azurerm_network_interface.nic[0].id
  ]

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name = "mdvmasks${var.region_code}${var.random_string}"

    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 100
    caching              = "ReadWrite"
  }

  tags = var.tags
}

resource "azurerm_virtual_machine_extension" "custom-script-extension" {
  depends_on = [
    azurerm_linux_virtual_machine.vm
  ]

  count = var.standalone == true ? 1 : 0

  virtual_machine_id = azurerm_linux_virtual_machine.vm[0].id

  name                 = "custom-script-extension"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({
    commandToExecute = <<-EOT
      /bin/bash -c "echo '${replace(base64encode(file("${path.module}/../scripts/bootstrap-ubuntu-tool-server.sh")), "'", "'\\''")}' | base64 -d > /tmp/bootstrap-ubuntu-tool-server.sh && \
      chmod +x /tmp/bootstrap-ubuntu-tool-server.sh && \
      /bin/bash /tmp/bootstrap-ubuntu-tool-server.sh '${data.external.ssh_public_key.result.public_key}'"
    EOT
  })

  tags = var.tags
}

## Create Private DNS Zone for AKS
##
resource "azurerm_private_dns_zone" "dns_aks" {
  count = var.standalone == true ? 1 : 0

  name                = "privatelink.${var.region}.azmk8s.io"
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

## Link Private DNS Zone for AKS to virtual network
##
resource "azurerm_private_dns_zone_virtual_network_link" "link_aks" {
  count = var.standalone == true ? 1 : 0

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_private_dns_zone.dns_aks
  ]

  name                  = "linkaks${var.region_code}${var.random_string}"
  resource_group_name   = azurerm_resource_group.rgwork.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_aks[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

## Create Private DNS Zone for Azure Container Registry
##
resource "azurerm_private_dns_zone" "dns_acr_main" {
  count = var.standalone == true ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

resource "azurerm_private_dns_zone" "dns_acr_regional" {
  count = var.standalone == true ? 1 : 0

  name                = "${var.region}.data.privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.rgwork.name

  tags = var.tags
}

## Link Private DNS Zone for Azure Container Registry to virtual network
##
resource "azurerm_private_dns_zone_virtual_network_link" "link_acr_main" {
  count = var.standalone == true ? 1 : 0

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_private_dns_zone.dns_acr_main,
    azurerm_private_dns_zone_virtual_network_link.link_aks
  ]

  name                  = "linkaksacr${var.region_code}${var.random_string}"
  resource_group_name   = azurerm_resource_group.rgwork.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_acr_main[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "link_acr_regional" {
  count = var.standalone == true ? 1 : 0

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_private_dns_zone.dns_acr_regional,
    azurerm_private_dns_zone_virtual_network_link.link_acr_main
  ]

  name                  = "linkaksacr${var.region_code}${var.random_string}"
  resource_group_name   = azurerm_resource_group.rgwork.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_acr_regional[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

