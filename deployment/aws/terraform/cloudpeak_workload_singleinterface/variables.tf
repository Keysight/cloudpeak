variable "access_key" {
    type = string
}

variable "secret_key" {
    type = string
}

variable "cpserver_vpc_id" {
}

variable "region" {
    type = string
    default = "us-east-1"
}

variable "userloginid" {
    type = string
}

variable "instance_type" {
    type = string
    default = "c5.xlarge"
}

variable "ec2_keypair_name" {
    type = string
    default = "CloudPeak_PubKey"
}

variable "vpc_cidr_block" {
    type = string
    default = "10.30.0.0/16"
}

variable "ebs_volume_size" {
    type = number
    default = 8
}

variable "instance_count" {
    type = number
    default = 1
}

variable "public_ip_association" {
    type = bool
    default = false
}
