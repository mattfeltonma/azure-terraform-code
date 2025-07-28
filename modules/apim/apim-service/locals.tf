locals {
    ## Standard naming convention for relevant resources
    apim_name_prefix = "apim"

    ## Variables specific to APIM
    dns_label = "apim${var.primary_location_code}${var.random_string}"
}