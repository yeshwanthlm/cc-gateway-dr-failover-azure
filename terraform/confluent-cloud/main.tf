terraform {
  required_version = ">= 1.0"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Environment for the clusters with Stream Governance (Schema Registry)
resource "confluent_environment" "main" {
  display_name = var.environment_name

  # Enable Stream Governance (Schema Registry) - Advanced Package
  stream_governance {
    package = "ADVANCED"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Primary Azure Cluster in East US
resource "confluent_kafka_cluster" "primary_cluster" {
  display_name = var.primary_cluster_name
  availability = var.availability
  cloud        = "AZURE"
  region       = var.primary_cluster_region

  basic {}

  environment {
    id = confluent_environment.main.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Service Account for Primary Cluster
resource "confluent_service_account" "primary_cluster_manager" {
  display_name = "${var.primary_cluster_name}-manager"
  description  = "Service account for primary Azure cluster management"
}

# API Key for Primary Cluster
# IMPORTANT: Created AFTER role binding so it inherits CloudClusterAdmin permissions
resource "confluent_api_key" "primary_cluster_api_key" {
  display_name = "${var.primary_cluster_name}-api-key"
  description  = "API Key for primary Azure Kafka cluster with CloudClusterAdmin role"
  owner {
    id          = confluent_service_account.primary_cluster_manager.id
    api_version = confluent_service_account.primary_cluster_manager.api_version
    kind        = confluent_service_account.primary_cluster_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.primary_cluster.id
    api_version = confluent_kafka_cluster.primary_cluster.api_version
    kind        = confluent_kafka_cluster.primary_cluster.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # Wait for role binding to be created first
  depends_on = [
    confluent_role_binding.primary_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# DR Azure Cluster in West US 2
resource "confluent_kafka_cluster" "dr_cluster" {
  display_name = var.dr_cluster_name
  availability = var.availability
  cloud        = "AZURE"
  region       = var.dr_cluster_region

  basic {}

  environment {
    id = confluent_environment.main.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Service Account for DR Cluster
resource "confluent_service_account" "dr_cluster_manager" {
  display_name = "${var.dr_cluster_name}-manager"
  description  = "Service account for DR Azure cluster management"
}

# API Key for DR Cluster
# IMPORTANT: Created AFTER role binding so it inherits CloudClusterAdmin permissions
resource "confluent_api_key" "dr_cluster_api_key" {
  display_name = "${var.dr_cluster_name}-api-key"
  description  = "API Key for DR Azure Kafka cluster with CloudClusterAdmin role"
  owner {
    id          = confluent_service_account.dr_cluster_manager.id
    api_version = confluent_service_account.dr_cluster_manager.api_version
    kind        = confluent_service_account.dr_cluster_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.dr_cluster.id
    api_version = confluent_kafka_cluster.dr_cluster.api_version
    kind        = confluent_kafka_cluster.dr_cluster.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # Wait for role binding to be created first
  depends_on = [
    confluent_role_binding.dr_cluster_admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# Poll for Schema Registry availability after environment creation
# Schema Registry provisioning is asynchronous - this polls until it's ready
resource "null_resource" "wait_for_schema_registry" {
  depends_on = [confluent_environment.main]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      echo "Waiting for Schema Registry to be provisioned in environment ${confluent_environment.main.id}..."

      # Poll for up to 5 minutes (60 attempts, 5 seconds apart)
      for i in {1..60}; do
        echo "Attempt $i/60: Checking if Schema Registry is available..."

        # Use Confluent Cloud API to check if Schema Registry exists
        RESPONSE=$(curl -s -u "${var.confluent_cloud_api_key}:${var.confluent_cloud_api_secret}" \
          "https://api.confluent.cloud/srcm/v3/clusters?environment=${confluent_environment.main.id}" || echo "")

        # Check if response contains a Schema Registry cluster
        if echo "$RESPONSE" | grep -q "lsrc-"; then
          echo "✓ Schema Registry is ready!"
          exit 0
        fi

        if [ $i -lt 60 ]; then
          echo "Schema Registry not yet available, waiting 5 seconds..."
          sleep 5
        fi
      done

      echo "ERROR: Schema Registry did not become available within 5 minutes"
      exit 1
    EOT

    interpreter = ["bash", "-c"]
  }

  triggers = {
    environment_id = confluent_environment.main.id
  }
}

# Schema Registry Cluster - Data Source
# Schema Registry is automatically enabled via the environment's stream_governance block
# This data source retrieves the Schema Registry cluster details
data "confluent_schema_registry_cluster" "main" {
  environment {
    id = confluent_environment.main.id
  }

  # Wait for Schema Registry to be available before reading
  depends_on = [
    confluent_environment.main,
    null_resource.wait_for_schema_registry
  ]
}

# Service Account for Schema Registry
resource "confluent_service_account" "schema_registry_manager" {
  display_name = "schema-registry-manager"
  description  = "Service account for Schema Registry management"
}

# API Key for Schema Registry
resource "confluent_api_key" "schema_registry_api_key" {
  display_name = "schema-registry-api-key"
  description  = "API Key for Schema Registry"
  owner {
    id          = confluent_service_account.schema_registry_manager.id
    api_version = confluent_service_account.schema_registry_manager.api_version
    kind        = confluent_service_account.schema_registry_manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.main.id
    api_version = data.confluent_schema_registry_cluster.main.api_version
    kind        = data.confluent_schema_registry_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # Wait for role binding and schema registry to be available
  depends_on = [
    confluent_role_binding.schema_registry_resource_owner,
    data.confluent_schema_registry_cluster.main
  ]

  lifecycle {
    prevent_destroy = false
  }
}

