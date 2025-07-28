locals {
  # Convert the region name to a unique abbreviation
  region_abbreviations = {
    "australiacentral"   = "acl",
    "australiacentral2"  = "acl2",
    "australiaeast"      = "ae",
    "australiasoutheast" = "ase",
    "brazilsouth"        = "brs",
    "brazilsoutheast"    = "bse",
    "canadacentral"      = "cnc",
    "canadaeast"         = "cne",
    "centralindia"       = "ci",
    "centralus"          = "cus",
    "centraluseuap"      = "ccy",
    "eastasia"           = "ea",
    "eastus"             = "eus",
    "eastus2"            = "eus2",
    "eastus2euap"        = "ecy",
    "francecentral"      = "frc",
    "francesouth"        = "frs",
    "germanynorth"       = "gn",
    "germanywestcentral" = "gwc",
    "israelcentral"      = "ilc",
    "italynorth"         = "itn",
    "japaneast"          = "jpe",
    "japanwest"          = "jpw",
    "jioindiacentral"    = "jic",
    "jioindiawest"       = "jiw",
    "koreacentral"       = "krc",
    "koreasouth"         = "krs",
    "mexicocentral"      = "mxc",
    "newzealandnorth"    = "nzn",
    "northcentralus"     = "ncus",
    "northeurope"        = "ne",
    "norwayeast"         = "nwe",
    "norwaywest"         = "nww",
    "polandcentral"      = "plc",
    "qatarcentral"       = "qac",
    "southafricanorth"   = "san",
    "southafricawest"    = "saw",
    "southcentralus"     = "scus",
    "southeastasia"      = "sea",
    "southindia"         = "si",
    "spaincentral"       = "spac"
    "swedencentral"      = "swc",
    "switzerlandnorth"   = "swn",
    "switzerlandwest"    = "sww",
    "uaecentral"         = "uaec",
    "uaenorth"           = "uaen",
    "uksouth"            = "uks",
    "ukwest"             = "ukw",
    "westcentralus"      = "wcus",
    "westeurope"         = "we",
    "westindia"          = "wi",
    "westus"             = "wus",
    "westus2"            = "wus2",
    "westus3"            = "wus3"
  }
  location_code = lookup(local.region_abbreviations, var.location, var.location)

  # Fixed variables
  law_purpose = "nsp"

  # Create the virtual network and cidr ranges
  vnet_cidr_wl = cidrsubnet(var.address_space_azure, 2, 0)
  


  # Add required tags and merge them with the provided tags
  required_tags = {
    created_date = timestamp()
    created_by   = data.azurerm_client_config.identity_config.object_id
  }

   # Configure the server OS and image
  image_preference_publisher = "canonical"
  image_preference_offer = "ubuntu-24_04-lts"
  image_preference_sku = "server"
  image_preference_version = "latest"
  
  # Enable Private Endpoint network policies so NSGs are honored and UDRs
  # applied to other subnets accept the less specific route
  private_endpoint_network_policies = "Enabled"

  # Configure standard naming convention for relevant resources
  vnet_name      = "vnet"
  flow_logs_name = "fl"

  # Configure some standard subnet names
  subnet_name_app  = "snet-app"
  subnet_name_bastion = "AzureBastionSubnet"
  subnet_name_svc  = "snet-svc"


  # Enable flow log retention policy for 7 days
  flow_logs_enabled                  = true
  flow_logs_retention_policy_enabled = true
  flow_logs_retention_days           = 7

  # Enable traffic anlaytics for the network security group and set the interval to 60 minutes
  traffic_analytics_enabled             = true
  traffic_analytics_interval_in_minutes = 60

  
  tags = merge(
    var.tags,
    local.required_tags
  )
}
