# VPC
resource "aws_vpc" "sai01_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "sai01-vpc" }
}

#Subnet
resource "aws_subnet" "sai01_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.sai01_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.sai01_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {  Name = "sai01-subnet-${count.index}" 
    "kubernetes.io/cluster/sai011-cluster" = "shared"
    "kubernetes.io/role/elb"                  = "1" }
}

#IG
resource "aws_internet_gateway" "sai01_igw" {
  vpc_id = aws_vpc.sai01_vpc.id
  tags = {  Name = "sai01-igw"   }
}

# Route Table 
resource "aws_route_table" "sai01_route_table" {
  vpc_id = aws_vpc.sai01_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sai01_igw.id
  }

  # If main Ec2 is in saparate VPC need this block to route traffic and communication for kube to ec2
   route {
    cidr_block                = "10.5.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }
  tags = {  Name = "sai01-route-table"  }
}

# Subnet Associate to Route Table 
resource "aws_route_table_association" "sai01_association" {
  count          = 2
  subnet_id      = aws_subnet.sai01_subnet[count.index].id
  route_table_id = aws_route_table.sai01_route_table.id
}

resource "aws_security_group" "sai01_cluster_sg" {
  name   = "sai01-cluster-sg"
  vpc_id = aws_vpc.sai01_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {  Name = "sai01-cluster-sg"   }
}

# Security Group 
resource "aws_security_group" "sai01_node_sg" {
  name   = "sai01-node-sg"
  vpc_id = aws_vpc.sai01_vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {  Name = "sai01-node-sg"  }
}

# EKS CLuster 
resource "aws_eks_cluster" "sai01" {
  name     = "sai01-cluster"
  role_arn = local.cluster_role_arn

  vpc_config {
    subnet_ids              = aws_subnet.sai01_subnet[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.sai01_cluster_sg.id]
  }
}

# Node Pool 
resource "aws_eks_node_group" "sai01" {
  cluster_name    = aws_eks_cluster.sai01.name
  node_group_name = "sai01-node-group"
  node_role_arn   = local.node_role_arn
  subnet_ids      = aws_subnet.sai01_subnet[*].id

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["m7i-flex.large"]
  remote_access {
    ec2_ssh_key               = var.ec2_key
    source_security_group_ids = [aws_security_group.sai01_node_sg.id]
  }
}

#EBS CSI Role 
data "aws_iam_role" "ebs_csi_role" {
  name = "AmazonEKS_EBS_CSI_DriverRole"
}

# EXISTING IAM ROLES (YOUR SETUP)
data "aws_iam_role" "cluster_role" {
  name = "sai01-cluster-role"
}

data "aws_iam_role" "node_role" {
  name = "sai01-node-group-role"
}

data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.sai01.name
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.sai01.name
}

# TLS Certificate
data "tls_certificate" "eks" {
  url = aws_eks_cluster.sai01.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

#Kubectl Provider
provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
  load_config_file       = false
}

# EXISTING IAM ROLE ARNs
locals {
  cluster_role_arn = "arn:aws:iam::Account-ID:role/sai01-cluster-role"
  node_role_arn    = "arn:aws:iam::Account-ID:role/sai01-node-group-role"
  ebs_csi_role_arn = "arn:aws:iam::Account-ID:role/AmazonEKS_EBS_CSI_DriverRole"
}

variable "ec2_key" {
  description = "The name of the SSH key pair to use for instances"
  type        = string
  default     = "Your EC2 Key name "
}

/*

SECOND TIME:
ONLY use : cluster ARN, node ARN, IRSA role ARN
Only manage : Addons, Updates 

*/
