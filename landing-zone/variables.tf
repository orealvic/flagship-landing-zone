variable "subscription_id" {
  description = "Azure subscription ID where workloads are deployed"
  type        = string
}

variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "canadacentral"
}

# Backend config also needed as variables so terraform_remote_state can read it
variable "tfstate_resource_group_name" {
  description = "Resource group holding the Terraform state SA"
  type        = string
  default     = "rg-flagship-platform-bootstrap"
}

variable "tfstate_storage_account_name" {
  description = "Storage account name for tfstate"
  type        = string
  default     = "stflagshiptf6m4cx3"
}

variable "tfstate_container_name" {
  description = "Container name for tfstate"
  type        = string
  default     = "tfstate"
}

variable "alert_email" {
  description = "Email for landing-zone alerts"
  type        = string
  default     = "victor.ugbor30@gmail.com"
}
