variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_location" {
  description = "Azure region for AKS cluster deployment"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "cc-gateway-rg"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "cc-gateway-aks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.36"
}

variable "vm_size" {
  description = "Azure VM size for worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "availability_zones" {
  description = "Availability zones for AKS node pool"
  type        = list(string)
  default     = ["1", "2"]
}

variable "dns_zone_name" {
  description = "Azure Private DNS Zone name for the gateway"
  type        = string
  default     = "axa.com"
}

variable "gateway_dns_record_name" {
  description = "DNS record name for the gateway (e.g., kafka.cc for kafka.cc.axa.com)"
  type        = string
  default     = "kafka.cc"
}

variable "gateway_lb_ip" {
  description = "LoadBalancer IP address for the gateway A record (will be updated after deployment)"
  type        = string
  default     = ""
}

variable "owner_email" {
  description = "Owner email address for Azure resource tags (required by Azure Policy)"
  type        = string
}
