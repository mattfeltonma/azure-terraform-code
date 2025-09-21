locals {
  # Create a map of Private DNS Zones to create
  private_dns_zones = {
    keyvault  = "privatelink.vaultcore.azure.net"
    storage   = "privatelink.blob.core.windows.net"
    search    = "privatelink.search.azure.com"
    openai    = "privatelink.openai.azure.com"
    ai        = "privatelink.services.ai.azure.com"
    cognitive = "privatelink.cognitiveservices.azure.com"
  }
}
