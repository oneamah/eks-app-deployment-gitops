data "aws_eks_cluster" "cluster" {
  count = var.deploy_helm ? 1 : 0
  name  = aws_eks_cluster.main.name

  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.deploy_helm ? 1 : 0
  name  = aws_eks_cluster.main.name

  depends_on = [aws_eks_cluster.main]
}

locals {
  helm_cluster_endpoint = try(data.aws_eks_cluster.cluster[0].endpoint, "https://127.0.0.1")
  helm_cluster_ca       = try(base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data), "")
  helm_cluster_token    = try(data.aws_eks_cluster_auth.cluster[0].token, "")
}

provider "aws" {
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = local.helm_cluster_endpoint
  cluster_ca_certificate = local.helm_cluster_ca
  token                  = local.helm_cluster_token
}

provider "helm" {
  kubernetes = {
    host                   = local.helm_cluster_endpoint
    cluster_ca_certificate = local.helm_cluster_ca
    token                  = local.helm_cluster_token
  }
}