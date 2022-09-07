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
        values       = ["Cloud_Peak_3.50.0.80"]
    }
}

locals {
    image_id = data.aws_ami.cp_server_image.id
}

resource "aws_vpc" "VPC_CPServer" {
  cidr_block    = var.vpc_cidr_block
  tags = {
    Name = "${var.userloginid}-VPC_CPServer-${local.image_id}"
  }
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_deploy_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:*",
          "iam:*",
          "sts:*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.userloginid}-CPServerDeployRole"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { 
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "" 
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
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

  location_type = "availability-zone"
  preferred_instance_types = ["${var.instance_type}"]
}

locals {
    vpc_subnet_cidr_block = "${format("%s.10.0/24", join(".",slice(split(".", var.vpc_cidr_block),0,2)))}"
}

resource "aws_subnet" "CP-Server_Subnet" {
  vpc_id        = aws_vpc.VPC_CPServer.id
  cidr_block    = local.vpc_subnet_cidr_block
  availability_zone = element(keys({ for az, details in data.aws_ec2_instance_type_offering.instance_az : az => details.instance_type}),0) 

  tags = {
    Name = "${var.userloginid}-CPServer-Subnet-${local.image_id}"
  }
}

resource "aws_internet_gateway" "CP-Server_IGateway" {
  vpc_id        = aws_vpc.VPC_CPServer.id
}

resource "aws_route_table" "CP-Server_RouteTable" {
  vpc_id = aws_vpc.VPC_CPServer.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.CP-Server_IGateway.id}"
  }
  tags = {
    Name = "${var.userloginid}-CPServer-RouteTable-${local.image_id}"
  }
}

resource "aws_route_table_association" "CP-Server_RA" {
  subnet_id      = "${aws_subnet.CP-Server_Subnet.id}"
  route_table_id = "${aws_route_table.CP-Server_RouteTable.id}"
}

resource "aws_default_security_group" "CP-Server_DefSecGroup" {
  vpc_id        = aws_vpc.VPC_CPServer.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${local.vpc_subnet_cidr_block}"]
  }
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${local.vpc_subnet_cidr_block}"]
  }
}

resource "aws_security_group" "CP-Server_SecGroup" {
  name          = "CPServSecGroup"
  vpc_id        = aws_vpc.VPC_CPServer.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = var.public_subnets == null ? ["${local.vpc_subnet_cidr_block}"]:concat(var.public_subnets,[local.vpc_subnet_cidr_block])
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = var.public_subnets == null ? ["${local.vpc_subnet_cidr_block}"]:concat(var.public_subnets,[local.vpc_subnet_cidr_block])
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.public_subnets == null ? ["${local.vpc_subnet_cidr_block}"]:concat(var.public_subnets,[local.vpc_subnet_cidr_block])
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name  = "${var.userloginid}-cpserver_iam_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "cp_server_instance" {
  ami           = local.image_id
  instance_type = var.instance_type
  key_name = var.ec2_keypair_name
  iam_instance_profile = "${aws_iam_instance_profile.ec2_profile.name}"
  availability_zone = element(keys({ for az, details in data.aws_ec2_instance_type_offering.instance_az : az => details.instance_type}),0)
  vpc_security_group_ids = [aws_security_group.CP-Server_SecGroup.id]
  root_block_device {
    volume_size = var.ebs_volume_size
  }
  tags = {
    Name = "${var.userloginid}-CPServer-${local.image_id}"
  }
  subnet_id = aws_subnet.CP-Server_Subnet.id
  associate_public_ip_address = var.public_ip_association 
}

output "public_ip" {
  value       = [aws_instance.cp_server_instance.*.public_ip]
  description = "The public IP of the CloudPeak server"
}

output "vpc_id" {
  value       = aws_vpc.VPC_CPServer.id
  description = "The ID of the VPC bound to CP server"
}

output "subnet_id" {
  value       = aws_subnet.CP-Server_Subnet.id
  description = "The subnet ID of the VPC bound to CP server"
}
