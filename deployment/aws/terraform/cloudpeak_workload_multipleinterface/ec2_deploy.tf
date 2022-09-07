terraform {
  required_providers {
    aws = {
      source    = "hashicorp/aws"
      version   = "~> 3.0"
    }
  }
}

provider "aws" {
    region = var.region
    access_key  = var.access_key
    secret_key  = var.secret_key
}

data "aws_ami" "cp_server_image" {

    owners           = ["self","aws-marketplace"]
    filter {
        name         = "name"
        values       = ["Cloud_Peak_Workload_3.50.0.80"]
    }
}

locals {
    image_id = data.aws_ami.cp_server_image.id
}

resource "aws_vpc" "VPC_CPWorkload" {
  cidr_block    = var.vpc_cidr_block
  tags = {
    Name = "${var.userloginid}-VPC_CPWorkload-${local.image_id}"
  }
}

data "aws_availability_zones" "all" {}

data "aws_ec2_instance_type_offering" "instance_az" {
  for_each = toset(data.aws_availability_zones.all.names)
  filter {
    name   = "instance-type"
    values = ["${var.instance_type}"]
  }
  filter {
    name   = "location"
    values = [each.value]
  }

  location_type             = "availability-zone"
  preferred_instance_types  = ["${var.instance_type}"]
}

locals {
    vpc_subnet_mgmt_cidr_block = "${format("%s.30.0/24", join(".",slice(split(".", var.vpc_cidr_block),0,2)))}"
    vpc_subnet_test_cidr_block = "${format("%s.35.0/24", join(".",slice(split(".", var.vpc_cidr_block),0,2)))}"
}

resource "aws_subnet" "CP-Workload_Subnet_Mgmt" {
  vpc_id            = aws_vpc.VPC_CPWorkload.id
  cidr_block        = local.vpc_subnet_mgmt_cidr_block
  availability_zone = element(keys({ for az, details in data.aws_ec2_instance_type_offering.instance_az : az => details.instance_type}),0) 

  tags = {
    Name = "${var.userloginid}-CPWorkload-SubnetMgmt-${local.image_id}"
  }
}

resource "aws_subnet" "CP-Workload_Subnet_Test" {
  vpc_id            = aws_vpc.VPC_CPWorkload.id
  cidr_block        = local.vpc_subnet_test_cidr_block
  availability_zone = element(keys({ for az, details in data.aws_ec2_instance_type_offering.instance_az : az => details.instance_type}),0) 

  tags = {
    Name = "${var.userloginid}-CPWorkload-SubnetTest-${local.image_id}"
  }
}

data "aws_vpc" "cp_server" {
  id = "${var.cpserver_vpc_id}"
}

resource "aws_vpc_peering_connection" "workload_to_server" {
  vpc_id        = aws_vpc.VPC_CPWorkload.id
  peer_vpc_id   = "${data.aws_vpc.cp_server.id}"
  
  auto_accept   = true
}

resource "aws_internet_gateway" "CP-Workload_IGateway" {
  vpc_id        = aws_vpc.VPC_CPWorkload.id
}

resource "aws_route_table" "CP-Workload_RouteTable" {
  vpc_id = aws_vpc.VPC_CPWorkload.id
  tags = {
    Name = "${var.userloginid}-CPWorkload-RouteTable-${local.image_id}"
  }
}

resource "aws_route" "workload_to_server" {
  route_table_id            = "${aws_route_table.CP-Workload_RouteTable.id}"
  destination_cidr_block    = "${data.aws_vpc.cp_server.cidr_block}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.workload_to_server.id}"
}

resource "aws_route_table_association" "CP-Workload_RA_Mgmt" {
  subnet_id      = "${aws_subnet.CP-Workload_Subnet_Mgmt.id}"
  route_table_id = "${aws_route_table.CP-Workload_RouteTable.id}"
}

resource "aws_route_table_association" "CP-Workload_RA_Test" {
  subnet_id      = "${aws_subnet.CP-Workload_Subnet_Test.id}"
  route_table_id = "${aws_route_table.CP-Workload_RouteTable.id}"
}

resource "aws_default_security_group" "CP-Workload_DefSecGroup" {
  vpc_id        = aws_vpc.VPC_CPWorkload.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${local.vpc_subnet_mgmt_cidr_block}"]
  }
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${local.vpc_subnet_mgmt_cidr_block}"]
  }
}

resource "aws_security_group" "CP-Workload_SecGroup" {
  name = "${var.userloginid}-CPWorkload-SecGroup-${local.image_id}"
  vpc_id        = aws_vpc.VPC_CPWorkload.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr_block}","${data.aws_vpc.cp_server.cidr_block}"]
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["${var.vpc_cidr_block}","${data.aws_vpc.cp_server.cidr_block}"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${var.vpc_cidr_block}","${data.aws_vpc.cp_server.cidr_block}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "wl_nic_mgmt" {
  count             = var.instance_count
  subnet_id         = "${aws_subnet.CP-Workload_Subnet_Mgmt.id}"
  security_groups   = [aws_security_group.CP-Workload_SecGroup.id]
}

resource "aws_network_interface" "wl_nic_test" {
  count             = var.instance_count
  subnet_id         = "${aws_subnet.CP-Workload_Subnet_Test.id}"
  security_groups   = [aws_security_group.CP-Workload_SecGroup.id]
}

resource "aws_instance" "cp_workload_instance" {
  count                     = var.instance_count
  ami                       = local.image_id
  instance_type             = var.instance_type
  key_name                  = var.ec2_keypair_name
  availability_zone         = element(keys({ for az, details in data.aws_ec2_instance_type_offering.instance_az : az => details.instance_type}),0)
  root_block_device {
    volume_size             = var.ebs_volume_size
    delete_on_termination   = true
  }
  network_interface {
      device_index = 0
      network_interface_id = aws_network_interface.wl_nic_mgmt[count.index].id
  }
  network_interface {
      device_index = 1
      network_interface_id = aws_network_interface.wl_nic_test[count.index].id 
  }
  tags = {
    Name = "${var.userloginid}-CPWorkload-${local.image_id}-${format("%02d", count.index + 1)}"
  }
}

output "private_ip" {
  value       = [aws_instance.cp_workload_instance.*.private_ip]
  description = "The private IP of the CloudPeak Workload"
}

output "vpc_id" {
  value       = aws_vpc.VPC_CPWorkload.id
  description = "The ID of the VPC bound to CP Workload"
}

output "subnet_id_mgmt" {
  value       = aws_subnet.CP-Workload_Subnet_Mgmt.id
  description = "The subnet ID of the VPC bound to CP Workload"
}
