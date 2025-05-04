provider "aws" {
  region = var.region
}

# VPC for EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# IAM roles for workers
resource "aws_iam_user" "worker_users" {
  count = 2
  name  = "eks-worker-${count.index + 1}"
}

resource "aws_iam_access_key" "worker_keys" {
  count = 2
  user  = aws_iam_user.worker_users[count.index].name
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable managed node group
  eks_managed_node_groups = {
    main = {
      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  # Map additional IAM users to EKS cluster
  aws_auth_users = [
    for i in range(2) : {
      userarn  = aws_iam_user.worker_users[i].arn
      username = aws_iam_user.worker_users[i].name
      groups   = ["system:masters"]
    }
  ]
}

# Output for kubectl access
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}

output "worker_access_keys" {
  description = "Access keys for worker users"
  sensitive   = true
  value = [
    for i in range(2) : {
      username   = aws_iam_user.worker_users[i].name
      access_key = aws_iam_access_key.worker_keys[i].id
      secret_key = aws_iam_access_key.worker_keys[i].secret
    }
  ]
}
