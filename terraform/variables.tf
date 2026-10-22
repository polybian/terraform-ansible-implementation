# Variables for the terraform-ansible-implementation deployment.
# Everything here is fictional placeholder data. Real values belong in a
# terraform.tfvars file that is never committed (see .gitignore and
# terraform.tfvars.example).

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID this implementation targets. The default is an all-zero placeholder, not a real subscription."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "project_name" {
  type        = string
  description = "Short name used as the prefix for every resource in this implementation."
  default     = "tfdemo"
}

variable "environment" {
  type        = string
  description = "Environment tag applied to all resources (demo, staging, prod)."
  default     = "demo"
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "centralus"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the demo VNet."
  default     = ["10.10.0.0/16"]
}

variable "subnet_address_prefixes" {
  type        = list(string)
  description = "Address prefixes for the demo subnet."
  default     = ["10.10.1.0/24"]
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed to reach the VM on SSH (port 22) through the NSG. REQUIRED — no default on purpose: SSH arrives over the public internet, so your source is your public IP (e.g. 203.0.113.25/32 from whatismyip), not an RFC1918 range. The old 10.0.0.0/8 default never matched real SSH traffic and silently locked everyone out. Keep this narrow — a /32 of your own public IP is ideal."
}

variable "vm_size" {
  type        = string
  description = "Azure VM SKU for the demo VM."
  default     = "Standard_B1s"
}

variable "admin_username" {
  type        = string
  description = "Local admin username created on the demo VM. SSH key auth only — password auth is disabled."
  default     = "demoadmin"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to your SSH public key (.pub) file. Used with pathexpand() so ~ works. Generate one with ssh-keygen; never commit key material."
  default     = "~/.ssh/id_demo.pub"
}
