locals {
  # Configure the NVA OS SKU
  image_preference_publisher = "canonical"
  image_preference_offer = "ubuntu-24_04-lts"
  image_preference_sku = "server"
  image_preference_version = "latest"

  # Enable Private Endpoint network policies so NSGs are honored and UDRs
  # applied to other subnets accept the less specific route
  private_endpoint_network_policies     = "Enabled"

  # Configure standard naming convention for relevant resources
  vnet_name = "vnet"
  flow_logs_name = "fl"
  dcr_association = "dcra"

  # Configure three character code for purpose of vnet
  vnet_purpose = "trs"

  # Configure some standard subnet names
  subnet_name_firewall_public        = "snet-nva-pub"
  subnet_name_firewall_private       = "snet-nva-pri"
}
