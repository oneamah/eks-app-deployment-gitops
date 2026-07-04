variable "cluster_name" {
  description = "The name of the Kubernetes cluster."
  type        = string
  default     = "my-eks-cluster"
}

variable "deploy_helm" {
  description = "Set to true after the EKS cluster exists to deploy Helm charts."
  type        = bool
  default     = false
}

variable "deploy_kubernetes" {
  description = "Set to true after the EKS cluster exists to deploy Kubernetes resources."
  type        = bool
  default     = false
}

variable "frontend_image" {
  description = "Container image for the Angular frontend application."
  type        = string
  default     = "ghcr.io/your-org/angular-frontend:latest"
}

variable "backend_image" {
  description = "Container image for the .NET backend API application."
  type        = string
  default     = "mcr.microsoft.com/dotnet/samples:aspnetapp"
}

variable "frontend_container_port" {
  description = "Container port exposed by the Angular frontend container."
  type        = number
  default     = 80
}

variable "frontend_replicas" {
  description = "Number of replicas for the Angular frontend deployment."
  type        = number
  default     = 2
}

variable "backend_replicas" {
  description = "Number of replicas for the .NET backend deployment."
  type        = number
  default     = 2
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID used for DNS records when deploy_kubernetes is true."
  type        = string
  default     = ""
}

variable "manage_static_route53_records" {
  description = "Set true to manage Route53 A alias records in Terraform; keep false when using external-dns with Ingress."
  type        = bool
  default     = false
}

variable "lb_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener on port 443."
  type        = string
  default     = null
}