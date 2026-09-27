variable "prefix" {
  description = "Short prefix for every resource name. Lowercase letters and digits, 3-12 characters."
  type        = string
  default     = "tordata"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.prefix))
    error_message = "prefix must be 3-12 lowercase letters or digits (storage account naming rules)."
  }
}

variable "location" {
  description = "Azure region. Canada Central keeps the data in the country."
  type        = string
  default     = "canadacentral"
}

variable "admin_object_id" {
  description = "Entra ID object ID of the administrator (az ad signed-in-user show --query id -o tsv). Defaults to whoever runs Terraform."
  type        = string
  default     = null
}

variable "databricks_sku" {
  description = "premium is required for Unity Catalog, which the notebooks use to reach the lake."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.databricks_sku)
    error_message = "databricks_sku must be standard or premium."
  }
}

variable "tags" {
  type = map(string)
  default = {
    project = "toronto-data-platform"
    managed = "terraform"
  }
}
