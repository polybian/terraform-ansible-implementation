terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.47.0"
    }
  }

  # Default: local backend. State lives in terraform.tfstate next to this
  # config. That is fine for a LAB; do not use it for anything real, and
  # never commit the .tfstate file (it can contain secrets).
  #
  # Remote-state template (commented out on purpose): uncomment, fill in,
  # and re-run `terraform init -migrate-state` to move state into an Azure
  # Storage Account. Blob leasing gives you the state lock, so two people
  # (or two CI jobs) cannot apply at the same time and corrupt state.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "<your-storage-account-name>"
  #   container_name       = "tfstate"
  #   key                  = "terraform-ansible-lab/terraform.tfstate"
  # }
}
