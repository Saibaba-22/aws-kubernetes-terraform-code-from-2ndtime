# aws-kubernetes-terraform-code-from-2ndtime
AWS Terraform Kubernetes Code from 2nd time only need to call or read policies, roles and create

This project is used when AWS IAM roles, policies, and OIDC are already created manually during the first setup.

From the second execution onward, Terraform only:

reads existing IAM roles
reads existing policies
creates EKS resources
creates node groups
installs addons
deploys Kubernetes manifests

No IAM role or policy creation is required.

Project Structure
aws-kubernetes-terraform-code-from-2ndtime/
│
├── provider.tf
├── eks.tf
├── nodegroup.tf
├── addons.tf
├── vpc.tf
├── variables.tf
├── outputs.tf
├── namespace.tf
├── deployment.tf
└── README.md
Prerequisites

Already created manually in AWS:

EKS Cluster IAM Role
Node Group IAM Role
EBS CSI Driver IAM Role
OIDC Provider
Required IAM Policies attached

Example roles:

sai01-cluster-role
sai01-node-group-role
AmazonEKS_EBS_CSI_DriverRole
Purpose

Avoid:

recreating IAM roles
recreating policies
Terraform printing large IAM JSON policy documents
duplicate IAM resources
IAM Role Reading Only
data "aws_iam_role" "cluster_role" {
  name = "sai01-cluster-role"
}

data "aws_iam_role" "node_role" {
  name = "sai01-node-group-role"
}

data "aws_iam_role" "ebs_csi_role" {
  name = "AmazonEKS_EBS_CSI_DriverRole"
}

locals {
  cluster_role_arn = data.aws_iam_role.cluster_role.arn
  node_role_arn    = data.aws_iam_role.node_role.arn
  ebs_csi_role_arn = data.aws_iam_role.ebs_csi_role.arn
}
EKS Cluster
resource "aws_eks_cluster" "sai01" {
  name     = "sai01-cluster"
  role_arn = local.cluster_role_arn

  vpc_config {
    subnet_ids = aws_subnet.sai01_subnet[*].id
  }
}
Node Group
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
}
EBS CSI Addon
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.sai01.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = local.ebs_csi_role_arn
}
Kubernetes Provider
data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.sai01.name
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.sai01.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.eks.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.eks.token
}
Kubectl Provider
provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.eks.certificate_authority[0].data
  )
  token            = data.aws_eks_cluster_auth.eks.token
  load_config_file = false
}
Advantages
Clean Terraform output
No IAM policy JSON printing
Faster execution
Reusable infrastructure
Easier production management
Avoids IAM duplication errors
Removed Resources

Do NOT include:

resource "aws_iam_role" ...
resource "aws_iam_policy" ...
resource "aws_iam_role_policy_attachment" ...
data "aws_iam_policy_document" ...
Terraform Commands

Initialize:

terraform init

Plan:

terraform plan

Apply:

terraform apply -auto-approve

Destroy:

terraform destroy -auto-approve
Expected Output

Terraform output becomes cleaner:

aws_eks_cluster.sai01: Creation complete
aws_eks_node_group.sai01: Creation complete
aws_eks_addon.ebs_csi: Creation complete

Instead of large IAM policy JSON documents.

Notes

This setup is recommended after initial AWS IAM and OIDC configuration is already completed manually or in a separate Terraform project.
