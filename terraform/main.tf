# terraform-ansible-lab — LAB infrastructure (azurerm provider).
# Demo pattern: one resource group, one VNet + subnet, an NSG with explicit
# rules, and a single Linux VM with key-only SSH. Nothing here is applied to
# a real cloud; see README.md for what was validated and what wasn't.

provider "azurerm" {
  features {}
  # Subscription comes from var.subscription_id so the config stays
  # portable between labs. No tenant/client secrets here — auth happens via
  # `az login` (Azure CLI) or environment variables on the operator's machine.
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = var.vnet_address_space

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-${var.project_name}-${var.environment}"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = var.subnet_address_prefixes
}

# NSG with explicit, ordered rules. The explicit deny-all at the end is the
# lab's default-deny posture; Azure already drops inbound by default, but
# spelling it out documents intent and shows up clearly in audits.
resource "azurerm_network_security_group" "lab" {
  name                = "nsg-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  description                 = "LAB: SSH from the operator's network only."
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.allowed_ssh_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab.name
}

resource "azurerm_network_security_rule" "allow_http_inside_vnet" {
  name                        = "allow-http-inside-vnet"
  description                 = "LAB: HTTP only between hosts in the lab VNet."
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab.name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "deny-all-inbound"
  description                 = "LAB: explicit default-deny for anything not matched above."
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab.name
}

resource "azurerm_public_ip" "lab" {
  name                = "pip-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_network_interface" "lab" {
  name                = "nic-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab.id
  }

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

# The single lab VM. Key-only SSH: no password, no real key material in the
# repo — the public key is read from the operator's disk at plan/apply time.
resource "azurerm_linux_virtual_machine" "lab" {
  name                            = "vm-${var.project_name}-${var.environment}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.lab.id]

  admin_ssh_key {
    username = var.admin_username
    # pathexpand() expands ~; file() reads the .pub at plan time. If the
    # file does not exist, plan fails loudly instead of deploying a VM
    # you cannot log into. That is the behavior you want.
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = azurerm_resource_group.lab.tags
}
