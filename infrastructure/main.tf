data "aws_availability_zones" "available" {
  state = "available"
}


resource "aws_ecr_repository" "frontend_app" {
  name                 = "frontend-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "backend_app" {
  name                 = "backend-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "frontend_chart" {
  name                 = "frontend-chart"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "backend_chart" {
  name                 = "backend-chart"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "random_shuffle" "azs" {
  input        = data.aws_availability_zones.available.names
  result_count = 2
}

locals {
  backend_namespace    = "backend"
  frontend_namespace   = "frontend"
  monitoring_namespace = "monitoring"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
  count                   = random_shuffle.azs.result_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index)
  availability_zone       = random_shuffle.azs.result[count.index]
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private" {
  count             = random_shuffle.azs.result_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index + random_shuffle.azs.result_count)
  availability_zone = random_shuffle.azs.result[count.index]
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table_association.public
  ]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = random_shuffle.azs.result_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  count          = random_shuffle.azs.result_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "vpc-endpoints-sg"
  description = "Allow VPC interface endpoint HTTPS from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "eks" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.eks"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_security_group" "lb" {
  name        = "lb-sg"
  description = "Allow inbound traffic to the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.deploy_kubernetes ? aws_acm_certificate_validation.frontend[0].certificate_arn : var.lb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  depends_on = [
    aws_acm_certificate_validation.frontend
  ]
}

resource "aws_lb_target_group" "main" {
  name     = "main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks.arn
  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]
}

resource "aws_iam_role" "eks" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role_policy_attachment" "eks_worker" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_registry" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "irsa_vpc_cni_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }
  }
}

resource "aws_iam_role" "irsa_vpc_cni" {
  name               = "eks-irsa-vpc-cni-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_vpc_cni_assume_role.json
}

resource "aws_iam_role_policy_attachment" "irsa_vpc_cni" {
  role       = aws_iam_role.irsa_vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_policy_document" "irsa_ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "irsa_ebs_csi" {
  name               = "eks-irsa-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "irsa_ebs_csi" {
  role       = aws_iam_role.irsa_ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_region" "current" {}

locals {
  eks_oidc_provider = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

data "aws_iam_policy_document" "irsa_alb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "irsa_alb_controller" {
  name               = "eks-irsa-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_alb_controller_assume_role.json
}

data "aws_iam_policy_document" "irsa_alb_controller_policy" {
  statement {
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeCapacityReservation",
      "elasticloadbalancing:DescribeAccountLimits",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:ModifyCapacityReservation",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "irsa_alb_controller" {
  name   = "eks-irsa-alb-controller-policy"
  policy = data.aws_iam_policy_document.irsa_alb_controller_policy.json
}

resource "aws_iam_role_policy_attachment" "irsa_alb_controller" {
  role       = aws_iam_role.irsa_alb_controller.name
  policy_arn = aws_iam_policy.irsa_alb_controller.arn
}

data "aws_iam_policy_document" "irsa_external_dns_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
  }
}

resource "aws_iam_role" "irsa_external_dns" {
  name               = "eks-irsa-external-dns-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_external_dns_assume_role.json
}

data "aws_iam_policy_document" "irsa_external_dns_policy" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "irsa_external_dns" {
  name   = "eks-irsa-external-dns-policy"
  policy = data.aws_iam_policy_document.irsa_external_dns_policy.json
}

resource "aws_iam_role_policy_attachment" "irsa_external_dns" {
  role       = aws_iam_role.irsa_external_dns.name
  policy_arn = aws_iam_policy.irsa_external_dns.arn
}

data "aws_iam_policy_document" "irsa_cluster_autoscaler_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "irsa_cluster_autoscaler" {
  name               = "eks-irsa-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_cluster_autoscaler_assume_role.json
}

data "aws_iam_policy_document" "irsa_cluster_autoscaler_policy" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "irsa_cluster_autoscaler" {
  name   = "eks-irsa-cluster-autoscaler-policy"
  policy = data.aws_iam_policy_document.irsa_cluster_autoscaler_policy.json
}

resource "aws_iam_role_policy_attachment" "irsa_cluster_autoscaler" {
  role       = aws_iam_role.irsa_cluster_autoscaler.name
  policy_arn = aws_iam_policy.irsa_cluster_autoscaler.arn
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  service_account_role_arn = aws_iam_role.irsa_vpc_cni.arn

  depends_on = [aws_iam_role_policy_attachment.irsa_vpc_cni]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
}

resource "helm_release" "metrics_server" {
  count            = var.deploy_helm ? 1 : 0
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "alb_ingress_controller" {
  count            = var.deploy_helm ? 1 : 0
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true

  set = [
    {
      name  = "clusterName"
      value = aws_eks_cluster.main.name
    },
    {
      name  = "region"
      value = data.aws_region.current.region
    },
    {
      name  = "vpcId"
      value = aws_vpc.main.id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.irsa_alb_controller.arn
    },
    {
      name  = "enableServiceMutatorWebhook"
      value = "false"
    }
  ]

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.irsa_alb_controller
  ]
}

resource "helm_release" "external_dns" {
  count            = var.deploy_helm ? 1 : 0
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true

  set = [
    {
      name  = "provider.name"
      value = "aws"
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-dns"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.irsa_external_dns.arn
    }
  ]

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.irsa_external_dns
  ]
}

resource "helm_release" "cert_manager" {
  count            = var.deploy_helm ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  upgrade_install  = true

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "cluster_autoscaler" {
  count            = var.deploy_helm ? 1 : 0
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = aws_eks_cluster.main.name
    },
    {
      name  = "awsRegion"
      value = data.aws_region.current.region
    },
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.irsa_cluster_autoscaler.arn
    }
  ]

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.irsa_cluster_autoscaler
  ]
}

resource "helm_release" "kube_state_metrics" {
  count            = var.deploy_helm ? 1 : 0
  name             = "kube-state-metrics"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-state-metrics"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "kube_prometheus_stack" {
  count            = var.deploy_helm ? 1 : 0
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  upgrade_install  = true

  values = [
    <<-EOT
    grafana:
      service:
        type: ClusterIP
      additionalDataSources:
        - name: Tempo
          type: tempo
          access: proxy
          url: http://tempo.monitoring.svc.cluster.local:3100
          isDefault: false
    prometheus:
      prometheusSpec:
        podMonitorSelectorNilUsesHelmValues: false
        serviceMonitorSelectorNilUsesHelmValues: false
    EOT
  ]

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "tempo" {
  count            = var.deploy_helm ? 1 : 0
  name             = "tempo"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  namespace        = "monitoring"
  create_namespace = true
  upgrade_install  = true

  values = [
    <<-EOT
    service:
      type: ClusterIP
    persistence:
      enabled: false
    tempo:
      receivers:
        otlp:
          protocols:
            grpc: {}
            http: {}
    EOT
  ]

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "otel_collector" {
  count            = var.deploy_helm ? 1 : 0
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  namespace        = "monitoring"
  create_namespace = true
  upgrade_install  = true

  values = [
    <<-EOT
    mode: deployment
    fullnameOverride: otel-collector
    image:
      repository: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s
    command:
      name: otelcol-k8s
    config:
      receivers:
        otlp:
          protocols:
            grpc: {}
            http: {}
      processors:
        batch: {}
      exporters:
        otlp:
          endpoint: tempo.monitoring.svc.cluster.local:4317
          tls:
            insecure: true
      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [batch]
            exporters: [otlp]
    EOT
  ]

  depends_on = [
    aws_eks_node_group.main,
    helm_release.tempo
  ]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.irsa_ebs_csi.arn

  depends_on = [aws_iam_role_policy_attachment.irsa_ebs_csi]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main-node-group"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = aws_subnet.private[*].id
  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_registry,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ecr_api,
    aws_vpc_endpoint.ecr_dkr,
    aws_vpc_endpoint.sts,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.logs,
    aws_vpc_endpoint.eks
  ]
}

resource "aws_iam_role" "node_group" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "helm_release" "gateway_api" {
  count            = var.deploy_helm && var.enable_gateway_api ? 1 : 0
  name             = "gateway-api"
  repository       = "oci://ghcr.io/nicklasfrahm/charts/gateway-api"
  chart            = "gateway-api"
  namespace        = "gateway-system"
  create_namespace = true
  upgrade_install  = true

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "argocd" {
  count            = var.deploy_helm ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  upgrade_install  = true

  set = [
    {
      name  = "server.service.type"
      value = "ClusterIP"
    }
  ]

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "argocd_rollouts" {
  count            = var.deploy_helm ? 1 : 0
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  upgrade_install  = true

  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_manifest" "backend_namespace" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = local.backend_namespace
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_manifest" "frontend_namespace" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = local.frontend_namespace
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_manifest" "backend_deployment" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "backend-rollout"
      namespace = local.backend_namespace
    }
    spec = {
      replicas = var.backend_replicas
      selector = {
        matchLabels = {
          app = "backend"
        }
      }
      strategy = {
        type = "RollingUpdate"
      }
      template = {
        metadata = {
          labels = {
            app = "backend"
          }
        }
        spec = {
          containers = [
            {
              name  = "backend-container"
              image = var.backend_image
              env = [
                {
                  name  = "ASPNETCORE_URLS"
                  value = "http://+:8080"
                },
                {
                  name  = "OTEL_SERVICE_NAME"
                  value = "backend-api"
                },
                {
                  name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
                  value = "http://otel-collector.monitoring.svc.cluster.local:4317"
                },
                {
                  name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
                  value = "grpc"
                }
              ]
              ports = [
                {
                  containerPort = 8080
                }
              ]
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_namespace]

}

resource "kubernetes_manifest" "frontend_deployment" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "frontend-rollout"
      namespace = local.frontend_namespace
    }
    spec = {
      replicas = var.frontend_replicas
      selector = {
        matchLabels = {
          app = "frontend"
        }
      }
      strategy = {
        type = "RollingUpdate"
      }
      template = {
        metadata = {
          labels = {
            app = "frontend"
          }
        }
        spec = {
          containers = [
            {
              name  = "frontend-container"
              image = var.frontend_image
              env = [
                {
                  name  = "OTEL_SERVICE_NAME"
                  value = "frontend-angular"
                },
                {
                  name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
                  value = "http://otel-collector.monitoring.svc.cluster.local:4318"
                },
                {
                  name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
                  value = "http/protobuf"
                }
              ]
              ports = [
                {
                  containerPort = var.frontend_container_port
                }
              ]
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.frontend_namespace]

}

resource "kubernetes_manifest" "gatewayClass" {
  count = var.deploy_kubernetes && var.deploy_crd_resources && var.enable_gateway_api ? 1 : 0
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "GatewayClass"
    metadata = {
      name = "my-gateway-class"
    }
    spec = {
      controllerName = "marmil.co/gateway-controller"
    }
  }

  depends_on = [helm_release.gateway_api]
}

resource "kubernetes_manifest" "gateway" {
  count = var.deploy_kubernetes && var.deploy_crd_resources && var.enable_gateway_api ? 1 : 0
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "my-gateway"
      namespace = local.frontend_namespace
    }
    spec = {
      gatewayClassName = "my-gateway-class"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
        },
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                name      = "my-tls-cert"
                namespace = local.frontend_namespace
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gatewayClass]
}

resource "kubernetes_manifest" "tls_certificate" {
  count = var.deploy_kubernetes && var.deploy_crd_resources ? 1 : 0
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "my-tls-cert"
      namespace = local.frontend_namespace
    }
    spec = {
      secretName = "my-tls-secret"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = ["marmil.co"]
    }
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "cluster_issuer" {
  count = var.deploy_kubernetes && var.deploy_crd_resources ? 1 : 0
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "your-email@example.com"
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "backend_service" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "backend-service"
      namespace = local.backend_namespace
    }
    spec = {
      selector = {
        app = "backend"
      }
      ports = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = 8080
        }
      ]
      type = "ClusterIP"
    }
  }

  depends_on = [kubernetes_manifest.backend_deployment]
}

resource "kubernetes_manifest" "backend_preview_service" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "backend-preview-service"
      namespace = local.backend_namespace
    }
    spec = {
      selector = {
        app = "backend"
      }
      ports = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = 8080
        }
      ]
      type = "ClusterIP"
    }
  }

  depends_on = [kubernetes_manifest.backend_deployment]
}

resource "kubernetes_manifest" "frontend_service" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "frontend-service"
      namespace = local.frontend_namespace
    }
    spec = {
      selector = {
        app = "frontend"
      }
      ports = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = var.frontend_container_port
        }
      ]
      type = "ClusterIP"
    }
  }

  depends_on = [kubernetes_manifest.frontend_deployment]
}

resource "kubernetes_manifest" "frontend_canary_service" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "frontend-canary-service"
      namespace = local.frontend_namespace
    }
    spec = {
      selector = {
        app = "frontend"
      }
      ports = [
        {
          protocol   = "TCP"
          port       = 80
          targetPort = var.frontend_container_port
        }
      ]
      type = "ClusterIP"
    }
  }

  depends_on = [kubernetes_manifest.frontend_deployment]
}

resource "kubernetes_manifest" "frontend_ingress" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "frontend-ingress"
      namespace = local.frontend_namespace
      annotations = {
        "kubernetes.io/ingress.class"               = "alb"
        "alb.ingress.kubernetes.io/group.name"      = "app-shared"
        "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"     = "ip"
        "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/certificate-arn" = "${aws_acm_certificate_validation.frontend[0].certificate_arn},${aws_acm_certificate_validation.backend[0].certificate_arn},${aws_acm_certificate_validation.monitoring[0].certificate_arn}"
        "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
        "external-dns.alpha.kubernetes.io/hostname" = "marmil.co"
      }
    }
    spec = {
      rules = [
        {
          host = "marmil.co"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "frontend-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.alb_ingress_controller,
    aws_acm_certificate_validation.frontend,
    aws_acm_certificate_validation.backend,
    aws_acm_certificate_validation.monitoring,
    kubernetes_manifest.frontend_service
  ]
}

resource "kubernetes_manifest" "backend_ingress" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "backend-ingress"
      namespace = local.backend_namespace
      annotations = {
        "kubernetes.io/ingress.class"               = "alb"
        "alb.ingress.kubernetes.io/group.name"      = "app-shared"
        "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"     = "ip"
        "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/certificate-arn" = "${aws_acm_certificate_validation.frontend[0].certificate_arn},${aws_acm_certificate_validation.backend[0].certificate_arn},${aws_acm_certificate_validation.monitoring[0].certificate_arn}"
        "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
        "external-dns.alpha.kubernetes.io/hostname" = "api.marmil.co"
      }
    }
    spec = {
      rules = [
        {
          host = "api.marmil.co"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "backend-service"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.alb_ingress_controller,
    aws_acm_certificate_validation.frontend,
    aws_acm_certificate_validation.backend,
    aws_acm_certificate_validation.monitoring,
    kubernetes_manifest.backend_service
  ]
}

resource "kubernetes_manifest" "monitoring_ingress" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "monitoring-ingress"
      namespace = local.monitoring_namespace
      annotations = {
        "kubernetes.io/ingress.class"               = "alb"
        "alb.ingress.kubernetes.io/group.name"      = "app-shared"
        "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"     = "ip"
        "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/certificate-arn" = "${aws_acm_certificate_validation.frontend[0].certificate_arn},${aws_acm_certificate_validation.backend[0].certificate_arn},${aws_acm_certificate_validation.monitoring[0].certificate_arn}"
        "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
        "external-dns.alpha.kubernetes.io/hostname" = "monitoring.marmil.co"
      }
    }
    spec = {
      rules = [
        {
          host = "monitoring.marmil.co"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kube-prometheus-stack-grafana"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.alb_ingress_controller,
    helm_release.kube_prometheus_stack,
    aws_acm_certificate_validation.frontend,
    aws_acm_certificate_validation.backend,
    aws_acm_certificate_validation.monitoring
  ]
}

resource "kubernetes_manifest" "frontend_route" {
  count = var.deploy_kubernetes && var.deploy_crd_resources && var.enable_gateway_api ? 1 : 0
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "frontend-route"
      namespace = local.frontend_namespace
    }
    spec = {
      parentRefs = [
        {
          name      = "my-gateway"
          namespace = local.frontend_namespace
        }
      ]
      hostnames = ["marmil.co"]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "frontend-service"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway, kubernetes_manifest.frontend_service]
}

resource "kubernetes_manifest" "backend_route" {
  count = var.deploy_kubernetes && var.deploy_crd_resources && var.enable_gateway_api ? 1 : 0
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "backend-route"
      namespace = local.frontend_namespace
    }
    spec = {
      parentRefs = [
        {
          name      = "my-gateway"
          namespace = local.frontend_namespace
        }
      ]
      hostnames = ["marmil.co"]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/api"
              }
            }
          ]
          backendRefs = [
            {
              name = "backend-service"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway, kubernetes_manifest.backend_service]
}

resource "kubernetes_manifest" "backend_network_policy" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "backend-network-policy"
      namespace = local.backend_namespace
    }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = local.frontend_namespace
                }
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.backend_namespace, kubernetes_manifest.frontend_namespace]

}

resource "kubernetes_manifest" "frontend_network_policy" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "frontend-network-policy"
      namespace = local.frontend_namespace
    }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = local.backend_namespace
                }
              }
            },
            {
              ipBlock = {
                cidr = "0.0.0.0/0"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.backend_namespace, kubernetes_manifest.frontend_namespace]

}

resource "kubernetes_manifest" "monitoring_network_policy" {
  count = var.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "monitoring-network-policy"
      namespace = local.monitoring_namespace
    }
    spec = {
      podSelector = {}
      policyTypes = ["Ingress"]
      ingress = [
        {
          from = [
            {
              ipBlock = {
                cidr = "0.0.0.0/0"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "aws_security_group" "eks_nodes" {
  name        = "eks-nodes-sg"
  description = "Allow inbound traffic to EKS nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_route53_record" "frontend" {
  count   = var.deploy_kubernetes && var.manage_static_route53_records ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "marmil.co"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "backend" {
  count   = var.deploy_kubernetes && var.manage_static_route53_records ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "api.marmil.co"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "monitoring" {
  count   = var.deploy_kubernetes && var.manage_static_route53_records ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "monitoring.marmil.co"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "frontend" {
  count             = var.deploy_kubernetes ? 1 : 0
  domain_name       = "marmil.co"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "backend" {
  count             = var.deploy_kubernetes ? 1 : 0
  domain_name       = "api.marmil.co"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "monitoring" {
  count             = var.deploy_kubernetes ? 1 : 0
  domain_name       = "monitoring.marmil.co"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "frontend_validation" {
  count           = var.deploy_kubernetes ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_route53_record" "backend_validation" {
  count           = var.deploy_kubernetes ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = tolist(aws_acm_certificate.backend[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.backend[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.backend[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_route53_record" "monitoring_validation" {
  count           = var.deploy_kubernetes ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = tolist(aws_acm_certificate.monitoring[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.monitoring[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.monitoring[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "frontend" {
  count                   = var.deploy_kubernetes ? 1 : 0
  certificate_arn         = aws_acm_certificate.frontend[0].arn
  validation_record_fqdns = [aws_route53_record.frontend_validation[0].fqdn]
}

resource "aws_acm_certificate_validation" "backend" {
  count                   = var.deploy_kubernetes ? 1 : 0
  certificate_arn         = aws_acm_certificate.backend[0].arn
  validation_record_fqdns = [aws_route53_record.backend_validation[0].fqdn]
}

resource "aws_acm_certificate_validation" "monitoring" {
  count                   = var.deploy_kubernetes ? 1 : 0
  certificate_arn         = aws_acm_certificate.monitoring[0].arn
  validation_record_fqdns = [aws_route53_record.monitoring_validation[0].fqdn]
}

resource "aws_lb_listener_certificate" "backend" {
  count           = var.deploy_kubernetes ? 1 : 0
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.backend[0].certificate_arn

  depends_on = [
    aws_acm_certificate_validation.backend,
    aws_lb_listener.https
  ]
}

resource "aws_lb_listener_certificate" "monitoring" {
  count           = var.deploy_kubernetes ? 1 : 0
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.monitoring[0].certificate_arn

  depends_on = [
    aws_acm_certificate_validation.monitoring,
    aws_lb_listener.https
  ]
}