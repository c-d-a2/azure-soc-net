data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "myrg" {
    name     = "socrg"
    location = "East US"
  }

resource "azurerm_virtual_network" "myvn" {
   name = "socvn"
   location = azurerm_resource_group.myrg.location
   resource_group_name = azurerm_resource_group.myrg.name
   address_space = ["172.16.0.0/16"]
   depends_on = [azurerm_resource_group.myrg]
}

resource "azurerm_subnet" "mysubnets" {
   for_each = var.sn
   name = each.value.name
   resource_group_name = azurerm_resource_group.myrg.name
   virtual_network_name = azurerm_virtual_network.myvn.name
   address_prefixes = each.value.address_prefixes
   depends_on = [azurerm_virtual_network.myvn]
}

# Public IP for Windows Server
resource "azurerm_public_ip" "windows_public_ip" {
  name                = "windows-server-public-ip"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [azurerm_resource_group.myrg]
}

# Public IP for Linux Server
resource "azurerm_public_ip" "linux_public_ip" {
  name                = "linux-server-public-ip"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [azurerm_resource_group.myrg]
}

resource "azurerm_network_interface" "my_nics" {
  for_each            = var.nic_confs
  name                = each.value.name
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name

  ip_configuration {
    name                          = each.value.ip_config_name
    subnet_id                     = azurerm_subnet.mysubnets[each.value.subnet_key].id
    private_ip_address_allocation = each.value.private_ip_address_allocation
    private_ip_address            = each.value.private_ip_address
    public_ip_address_id          = each.value.nic_type == "windows" ? azurerm_public_ip.windows_public_ip.id : azurerm_public_ip.linux_public_ip.id
  }

  depends_on = [azurerm_subnet.mysubnets, azurerm_public_ip.windows_public_ip, azurerm_public_ip.linux_public_ip]
}

resource "azurerm_storage_account" "my_storage_account" {
  name                     = "socnet"
  resource_group_name      = azurerm_resource_group.myrg.name
  location                 = azurerm_resource_group.myrg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "staging"
  }
  depends_on = [azurerm_resource_group.myrg]
}
resource "azurerm_linux_virtual_machine" "my_linux_vms" {
  for_each              = var.linux_vms
  name                  = each.value.name
  location              = azurerm_resource_group.myrg.location
  resource_group_name   = azurerm_resource_group.myrg.name
  network_interface_ids = [azurerm_network_interface.my_nics[each.value.nic_id].id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "${each.value.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name  = each.value.name
  admin_username = var.username
  admin_password = var.password
  disable_password_authentication = false

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }
  depends_on = [
    azurerm_network_interface.my_nics,
    azurerm_storage_account.my_storage_account,
    azurerm_network_interface_security_group_association.linux_nsg_assoc
  ]
}


resource "azurerm_windows_virtual_machine" "my_win_vms" {
  for_each              = var.win_vms
  name                  = each.value.name
  admin_username        = var.username
  admin_password        = var.password
  location              = azurerm_resource_group.myrg.location
  resource_group_name   = azurerm_resource_group.myrg.name
  network_interface_ids = [azurerm_network_interface.my_nics[each.value.nic_id].id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "${each.value.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }


  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }
  depends_on = [
    azurerm_network_interface.my_nics,
    azurerm_storage_account.my_storage_account,
    azurerm_network_interface_security_group_association.windows_nsg_assoc
  ]
}




resource "azurerm_key_vault" "mykeyvault" {
  name                        = "treasurechest"
  location                    = azurerm_resource_group.myrg.location
  resource_group_name         = azurerm_resource_group.myrg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
  depends_on = [azurerm_resource_group.myrg]
}




resource "azurerm_log_analytics_workspace" "my_log_analytics_workspace" {
  name                = "soc-wp"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  depends_on = [azurerm_resource_group.myrg]
}
# Add NSGs after the subnet resource
resource "azurerm_network_security_group" "windows_nsg" {
  name                = "windows-server-nsg"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  depends_on = [azurerm_resource_group.myrg]
}

resource "azurerm_network_security_group" "linux_nsg" {
  name                = "linux-server-nsg"
  location            = azurerm_resource_group.myrg.location
  resource_group_name = azurerm_resource_group.myrg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  depends_on = [azurerm_resource_group.myrg]
}

# Add NSG associations after the network_interface resource
resource "azurerm_network_interface_security_group_association" "windows_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.my_nics["windows_server"].id
  network_security_group_id = azurerm_network_security_group.windows_nsg.id
  depends_on = [
    azurerm_network_interface.my_nics,
    azurerm_network_security_group.windows_nsg
  ]
}

resource "azurerm_network_interface_security_group_association" "linux_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.my_nics["ubuntu_server"].id
  network_security_group_id = azurerm_network_security_group.linux_nsg.id
  depends_on = [
    azurerm_network_interface.my_nics,
    azurerm_network_security_group.linux_nsg
  ]
}

