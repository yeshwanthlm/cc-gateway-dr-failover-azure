variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Confluent Cloud Environment Name"
  type        = string
  default     = "cc-gateway-demo-azure"
}

variable "primary_cluster_name" {
  description = "Name for the Primary Azure Kafka cluster"
  type        = string
  default     = "azure-eastus-primary"
}

variable "primary_cluster_region" {
  description = "Azure region for the Primary Kafka cluster"
  type        = string
  default     = "eastus"
}

variable "dr_cluster_name" {
  description = "Name for the DR Azure Kafka cluster"
  type        = string
  default     = "azure-westus2-dr"
}

variable "dr_cluster_region" {
  description = "Azure region for the DR Kafka cluster"
  type        = string
  default     = "westus2"
}

variable "availability" {
  description = "Availability zone configuration (SINGLE_ZONE or MULTI_ZONE)"
  type        = string
  default     = "SINGLE_ZONE"
}
