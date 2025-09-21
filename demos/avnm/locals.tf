locals {
  # Environments
  hub_environments = ["prod", "nonprod"]
  workload_environments = [
    {
      env = "prod"
      region = var.region_prod
      region_code = local.location_code_prod
      address_space = local.vnet_cidr_wl1_prod
      db_vm = true
    },
    {
      env = "pci"
      region = var.region_prod
      region_code = local.location_code_prod
      address_space = local.vnet_cidr_wl1_pci
      db_vm = false
    },
    {
      env = "nonprod"
      region = var.region_nonprod
      region_code = local.location_code_nonprod
      address_space = local.vnet_cidr_wl1_nonprod
      db_vm = true
    }
  ]

  # Router ASNs for each environment
  router_asn = {
    "prod"    = 65001,
    "nonprod" = 65002
  }

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
  location_code_prod = lookup(local.region_abbreviations, var.region_prod, var.region_prod)
  location_code_nonprod = lookup(local.region_abbreviations, var.region_nonprod, var.region_nonprod)

  # Create the virtual network cidr ranges
  vnet_cidr_tr_prod = cidrsubnet(var.address_space_azure_prod, 2, 0)
  vnet_cidr_wl1_prod = cidrsubnet(var.address_space_azure_prod, 2, 1)
  vnet_cidr_wl1_pci = cidrsubnet(var.address_space_azure_prod, 2, 2)
  vnet_cidr_tr_nonprod = cidrsubnet(var.address_space_azure_nonprod, 2, 0)
  vnet_cidr_wl1_nonprod = cidrsubnet(var.address_space_azure_nonprod, 2, 1)

  # Add required tags and merge them with the provided tags
  required_tags = {
    created_date = timestamp()
    created_by   = data.azurerm_client_config.identity_config.object_id
  }

  # Names for IPAM pools
  org_onprem_pool_name = "pool-org-onprem"
  org_pool_name = "pool-org-cloud"
  prod_pool_name = "pool-prod-cloud"
  nonprod_pool_name = "pool-nonprod-cloud"
  bu_prod_pool_name = "pool-bu-prod-cloud"
  bu_nonprod_pool_name = "pool-bu-nonprod-cloud"

  # Names for IPAM allocations
  org_allocation_onprem_lab_name = "allocation-org-onprem-lab"

  #
  
  tags = merge(
    var.tags,
    local.required_tags
  )
}
