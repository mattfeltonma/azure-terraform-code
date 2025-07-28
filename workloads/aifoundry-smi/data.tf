# Get the current subscription id
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "identity_config" { }

# Get the keys returned from the Bing Search resource
data "azapi_resource_action" "bing_api_keys" {
    depends_on = [ 
        azapi_resource.bing_grounding_search 
    ]

    type = "Microsoft.Bing/accounts@2020-06-10"
    resource_id = azapi_resource.bing_grounding_search.id
    action = "listKeys"
    method = "POST"
    response_export_values = ["key1", "key2"]
}