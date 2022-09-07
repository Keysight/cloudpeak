variable "access_key" {
    type = string
}

variable "secret_key" {
    type = string
}

variable "userloginid" {
    type = string
}

variable "region" {
    type = string
    default = "us-east-1"
}

variable "instance_type" {
    type = string
    default = "t3.xlarge"
}

variable "ec2_keypair_name" {
    type = string
}

variable "vpc_cidr_block" {
    type = string
    default = "192.168.0.0/16"
    description = "The CIDR block for the VPC for CloudPeak Management instance"
}

variable "public_subnets" {
    type = list
}

variable "ebs_volume_size" {
    type = number
    default = 50
}

variable "public_ip_association" {
    type = bool
    default = true
}
