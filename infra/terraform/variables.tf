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

variable "enable_fabric" {
  description = "Add the Microsoft Fabric serving layer (fabric.tf). A Fabric capacity bills while it runs; pause it when idle."
  type        = bool
  default     = false
}

variable "fabric_sku" {
  description = "Fabric capacity size. F2 is the smallest and is enough for this data volume."
  type        = string
  default     = "F2"

  validation {
    condition     = can(regex("^F(2|4|8|16|32|64|128|256|512|1024|2048)$", var.fabric_sku))
    error_message = "fabric_sku must be an F SKU, for example F2."
  }
}

variable "fabric_admin_upn" {
  description = "User principal name (user@domain) of the Fabric capacity administrator. Required when enable_fabric is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_fabric || var.fabric_admin_upn != null
    error_message = "Set fabric_admin_upn when enable_fabric is true."
  }
}
