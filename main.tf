# Providers used in this configuration

provider "azurerm" {
# subscription_id = "REPLACE-WITH-YOUR-SUBSCRIPTION-ID"
# client_id       = "REPLACE-WITH-YOUR-CLIENT-ID"
# client_secret   = "REPLACE-WITH-YOUR-CLIENT-SECRET"
# tenant_id       = "REPLACE-WITH-YOUR-TENANT-ID"
}

provider "random" {}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix}-rg"
  location = "${var.location}"
  tags     = "${var.tags}"
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_prefix}-vnet"
  location            = "${azurerm_resource_group.rg.location}"
  address_space       = ["${var.address_space}"]
  resource_group_name = "${azurerm_resource_group.rg.name}"
  dns_servers         = "${var.dns_servers}"
  tags                = "${var.tags}"
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.subnet_name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  address_prefix       = "${var.subnet_prefix}"
  service_endpoints    = ["${var.service_endpoints}"]
}

# Create a network security group
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.resource_prefix}-nsg"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  tags                = "${var.tags}"
}

# Create network security group rules to secure HDInsight management traffic
resource "azurerm_network_security_rule" "nsg_rule_allow_hdi_mgmt_traffic" {
  name                        = "allow_hdi_mgmt_traffic"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  source_address_prefixes     = ["${var.source_address_prefixes_mgmt}"]
  destination_port_range      = "443"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = "${azurerm_resource_group.rg.name}"
  network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_network_security_rule" "nsg_rule_allow_azure_resolver_traffic" {
  name                        = "allow_azure_resolver_traffic"
  priority                    = 301
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  source_address_prefix       = "${var.source_address_prefix_resolver}"
  destination_port_range      = "443"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = "${azurerm_resource_group.rg.name}"
  network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_network_security_rule" "nsg_rule_allow_hdi_mgmt_traffic_regional" {
  name                        = "allow_hdi_mgmt_traffic_regional"
  priority                    = 302
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  source_address_prefixes     = ["${var.source_address_prefixes_mgmt_region}"]
  destination_port_range      = "443"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = "${azurerm_resource_group.rg.name}"
  network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_subnet_network_security_group_association" "subnet_to_nsg" {
  subnet_id                 = "${azurerm_subnet.subnet.id}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
}

# Create storage accounts

resource "random_id" "storage_account_name_unique" {
  count       = "${var.storage_account_count}"
  byte_length = 8
}

resource "azurerm_storage_account" "storage" {
  count                    = "${var.storage_account_count}"
  name                     = "${element(random_id.storage_account_name_unique.*.hex, count.index)}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  access_tier              = "Hot"
  account_replication_type = "${var.account_replication_type}"

  network_rules {
    ip_rules                   = ["127.0.0.1"]
    virtual_network_subnet_ids = ["${azurerm_subnet.subnet.id}"]
  }

  tags = "${var.tags}"
}

# Create SQL Databases
resource "random_id" "sql_dbserver_name_unique" {
  byte_length = 8
}

resource "azurerm_sql_server" "dbserver" {
  count                        = "${length(var.azuresqldb_databases) > 0 ? 1 : 0}"
  name                         = "${random_id.sql_dbserver_name_unique.hex}"
  resource_group_name          = "${azurerm_resource_group.rg.name}"
  location                     = "${azurerm_resource_group.rg.location}"
  version                      = "12.0"
  administrator_login          = "${var.sql_server_admin_user}"
  administrator_login_password = "${var.sql_server_admin_password}"
  tags                         = "${var.tags}"
}

# Enables the "Allow Access to Azure services" box as described in the API docs 
# https://docs.microsoft.com/en-us/rest/api/sql/firewallrules/createorupdate

resource "azurerm_sql_firewall_rule" "sqlfw" {
  count               = "${length(var.azuresqldb_databases) > 0 ? 1 : 0}"
  name                = "allow-azure-services"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  server_name         = "${azurerm_sql_server.dbserver.name}"
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_sql_virtual_network_rule" "sqlvnet" {
  count               = "${length(var.azuresqldb_databases) > 0 ? 1 : 0}"
  name                = "allow-vnet"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  server_name         = "${azurerm_sql_server.dbserver.name}"
  subnet_id           = "${azurerm_subnet.subnet.id}"
}

resource "azurerm_sql_database" "sqldatabase" {
  count                            = "${length(var.azuresqldb_databases)}"
  name                             = "${var.azuresqldb_databases[count.index]}"
  resource_group_name              = "${azurerm_resource_group.rg.name}"
  location                         = "${azurerm_resource_group.rg.location}"
  edition                          = "Basic"
  collation                        = "SQL_Latin1_General_CP1_CI_AS"
  create_mode                      = "Default"
  requested_service_objective_name = "Basic"
  server_name                      = "${azurerm_sql_server.dbserver.name}"
}
