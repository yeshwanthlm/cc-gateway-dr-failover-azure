output "environment_id" {
  description = "Confluent Cloud Environment ID"
  value       = confluent_environment.main.id
}

output "primary_cluster_id" {
  description = "Primary Azure Kafka Cluster ID"
  value       = confluent_kafka_cluster.primary_cluster.id
}

output "primary_cluster_bootstrap_endpoint" {
  description = "Primary Azure Kafka Cluster Bootstrap Endpoint"
  value       = confluent_kafka_cluster.primary_cluster.bootstrap_endpoint
}

output "primary_cluster_rest_endpoint" {
  description = "Primary Azure Kafka Cluster REST Endpoint"
  value       = confluent_kafka_cluster.primary_cluster.rest_endpoint
}

output "primary_cluster_api_key" {
  description = "Primary Azure Kafka Cluster API Key"
  value       = confluent_api_key.primary_cluster_api_key.id
  sensitive   = true
}

output "primary_cluster_api_secret" {
  description = "Primary Azure Kafka Cluster API Secret"
  value       = confluent_api_key.primary_cluster_api_key.secret
  sensitive   = true
}

output "dr_cluster_id" {
  description = "DR Azure Kafka Cluster ID"
  value       = confluent_kafka_cluster.dr_cluster.id
}

output "dr_cluster_bootstrap_endpoint" {
  description = "DR Azure Kafka Cluster Bootstrap Endpoint"
  value       = confluent_kafka_cluster.dr_cluster.bootstrap_endpoint
}

output "dr_cluster_rest_endpoint" {
  description = "DR Azure Kafka Cluster REST Endpoint"
  value       = confluent_kafka_cluster.dr_cluster.rest_endpoint
}

output "dr_cluster_api_key" {
  description = "DR Azure Kafka Cluster API Key"
  value       = confluent_api_key.dr_cluster_api_key.id
  sensitive   = true
}

output "dr_cluster_api_secret" {
  description = "DR Azure Kafka Cluster API Secret"
  value       = confluent_api_key.dr_cluster_api_key.secret
  sensitive   = true
}

output "connection_details" {
  description = "Connection details for both clusters"
  value = {
    primary_cluster = {
      cluster_id        = confluent_kafka_cluster.primary_cluster.id
      bootstrap_servers = confluent_kafka_cluster.primary_cluster.bootstrap_endpoint
      rest_endpoint     = confluent_kafka_cluster.primary_cluster.rest_endpoint
      region            = var.primary_cluster_region
      cloud             = "AZURE"
    }
    dr_cluster = {
      cluster_id        = confluent_kafka_cluster.dr_cluster.id
      bootstrap_servers = confluent_kafka_cluster.dr_cluster.bootstrap_endpoint
      rest_endpoint     = confluent_kafka_cluster.dr_cluster.rest_endpoint
      region            = var.dr_cluster_region
      cloud             = "AZURE"
    }
  }
}

# Service Account IDs (needed for creating ACLs)
output "primary_service_account_id" {
  description = "Primary cluster service account ID (for ACL creation)"
  value       = confluent_service_account.primary_cluster_manager.id
}

output "dr_service_account_id" {
  description = "DR cluster service account ID (for ACL creation)"
  value       = confluent_service_account.dr_cluster_manager.id
}

# Schema Registry Outputs
output "schema_registry_id" {
  description = "Schema Registry Cluster ID"
  value       = data.confluent_schema_registry_cluster.main.id
}

output "schema_registry_endpoint" {
  description = "Schema Registry REST Endpoint (Public)"
  value       = data.confluent_schema_registry_cluster.main.rest_endpoint
}

output "schema_registry_api_key" {
  description = "Schema Registry API Key"
  value       = confluent_api_key.schema_registry_api_key.id
  sensitive   = true
}

output "schema_registry_api_secret" {
  description = "Schema Registry API Secret"
  value       = confluent_api_key.schema_registry_api_key.secret
  sensitive   = true
}

output "schema_registry_service_account_id" {
  description = "Schema Registry service account ID"
  value       = confluent_service_account.schema_registry_manager.id
}

output "bootstrap_instructions" {
  description = "One-time bootstrap instructions for Terraform automation"
  value       = <<-EOT

    ╔════════════════════════════════════════════════════════════════╗
    ║  ONE-TIME BOOTSTRAP REQUIRED                                   ║
    ╠════════════════════════════════════════════════════════════════╣
    ║  To enable full Terraform automation, grant your Cloud API key ║
    ║  OrganizationAdmin permissions (one-time manual step).         ║
    ║                                                                 ║
    ║  1. Go to: https://confluent.cloud/settings/api-keys          ║
    ║  2. Find your Cloud API key                                    ║
    ║  3. Add role: OrganizationAdmin                                ║
    ║  4. Run: terraform apply                                       ║
    ║                                                                 ║
    ║  After this, everything is managed by Terraform!               ║
    ║                                                                 ║
    ║  See: README.md for detailed instructions                      ║
    ╚════════════════════════════════════════════════════════════════╝

  EOT
}

output "terraform_managed_resources" {
  description = "List of resources managed by Terraform after bootstrap"
  value       = <<-EOT

    After bootstrap, Terraform manages:

    Infrastructure:
      ✓ Environment: ${confluent_environment.main.id}
      ✓ Primary Cluster (Azure ${var.primary_cluster_region}): ${confluent_kafka_cluster.primary_cluster.id}
      ✓ DR Cluster (Azure ${var.dr_cluster_region}): ${confluent_kafka_cluster.dr_cluster.id}
      ✓ Schema Registry (Advanced, Public): ${data.confluent_schema_registry_cluster.main.id}
      ✓ Service Accounts: 3 (Primary, DR, Schema Registry)
      ✓ API Keys: 3 cluster-specific keys

    Access Control (after bootstrap):
      ✓ Role Bindings: CloudClusterAdmin (Kafka), ResourceOwner (Schema Registry)
      ✓ Fully managed by Terraform

  EOT
}
