#!/bin/bash

# =============================================================================
# Confluent Cloud Gateway Demo - Deployment Script (Azure)
# =============================================================================
# This script automates the complete deployment of:
# - Azure AKS Cluster
# - Confluent Cloud Kafka Clusters (Azure Primary & DR)
# - Schema Registry with Advanced Governance Package
# - Confluent Gateway on Kubernetes
# - All necessary certificates and secrets
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
    print_success "$1 is installed"
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

print_header "Pre-flight Checks"

# Check required commands
check_command terraform
check_command az
check_command kubectl
check_command helm
check_command openssl
check_command keytool

# Check for .env file
if [ ! -f .env ]; then
    print_error ".env file not found!"
    print_info "Please copy .env.example to .env and fill in your configuration"
    print_info "  cp .env.example .env"
    print_info "  # Edit .env with your values"
    exit 1
fi

# Load environment variables
print_info "Loading configuration from .env file..."
export $(cat .env | grep -v '^#' | xargs)
print_success "Configuration loaded"

# Validate required variables
REQUIRED_VARS=(
    "AZURE_SUBSCRIPTION_ID"
    "OWNER_EMAIL"
    "AZURE_LOCATION"
    "RESOURCE_GROUP_NAME"
    "AKS_CLUSTER_NAME"
    "CONFLUENT_CLOUD_API_KEY"
    "CONFLUENT_CLOUD_API_SECRET"
    "GATEWAY_DOMAIN"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required variable $var is not set in .env file"
        exit 1
    fi
done
print_success "All required variables are set"

# Check Azure credentials
print_info "Checking Azure credentials..."
if ! az account show &> /dev/null; then
    print_error "Azure credentials not configured. Please run: az login"
    exit 1
fi
print_success "Azure credentials are valid"

# Set Azure subscription
print_info "Setting Azure subscription..."
az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
print_success "Azure subscription set to: ${AZURE_SUBSCRIPTION_ID}"

# -----------------------------------------------------------------------------
# Step 1: Deploy AKS Cluster
# -----------------------------------------------------------------------------

print_header "Step 1: Deploying AKS Cluster"

cd terraform/aks

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
azure_subscription_id   = "${AZURE_SUBSCRIPTION_ID}"
owner_email             = "${OWNER_EMAIL}"
azure_location          = "${AZURE_LOCATION}"
resource_group_name     = "${RESOURCE_GROUP_NAME}"
cluster_name            = "${AKS_CLUSTER_NAME}"
kubernetes_version      = "${KUBERNETES_VERSION:-1.36}"
vm_size                 = "${VM_SIZE:-Standard_D2s_v3}"
availability_zones      = [$(echo ${AVAILABILITY_ZONES:-1,2} | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')]
dns_zone_name           = "${DNS_ZONE_NAME:-axa.com}"
gateway_dns_record_name = "${GATEWAY_DNS_RECORD_NAME:-kafka.cc}"
gateway_lb_ip           = ""
EOF

print_info "Initializing Terraform..."
terraform init

print_info "Deploying AKS cluster (this may take 10-15 minutes)..."
terraform apply -auto-approve

print_success "AKS cluster deployed successfully"

# Configure kubectl
print_info "Configuring kubectl..."
az aks get-credentials --resource-group ${RESOURCE_GROUP_NAME} --name ${AKS_CLUSTER_NAME} --overwrite-existing
print_success "kubectl configured"

# Verify cluster access
print_info "Verifying cluster access..."
kubectl get nodes
print_success "Cluster is accessible"

cd ../..

# -----------------------------------------------------------------------------
# Step 2: Install Confluent Operator
# -----------------------------------------------------------------------------

print_header "Step 2: Installing Confluent Operator"

print_info "Adding Confluent Helm repository..."
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

print_info "Creating confluent namespace..."
kubectl create namespace confluent 2>/dev/null || print_warning "Namespace confluent already exists, continuing..."

print_info "Installing Confluent for Kubernetes operator..."
helm upgrade --install confluent-operator \
    confluentinc/confluent-for-kubernetes \
    --namespace confluent \
    --wait

print_success "Confluent operator installed successfully"

# Wait for operator to be ready
print_info "Waiting for operator pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=confluent-operator -n confluent --timeout=300s
print_success "Confluent operator is ready"

# -----------------------------------------------------------------------------
# Step 3: Deploy Confluent Cloud Clusters with ACLs
# -----------------------------------------------------------------------------

print_header "Step 3: Deploying Confluent Cloud Clusters"

cd terraform/confluent-cloud

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
confluent_cloud_api_key    = "${CONFLUENT_CLOUD_API_KEY}"
confluent_cloud_api_secret = "${CONFLUENT_CLOUD_API_SECRET}"
environment_name           = "${CONFLUENT_ENVIRONMENT_NAME:-cc-gateway-demo-azure}"
primary_cluster_name       = "${PRIMARY_CLUSTER_NAME:-azure-eastus-primary}"
primary_cluster_region     = "${PRIMARY_CLUSTER_REGION:-eastus}"
dr_cluster_name            = "${DR_CLUSTER_NAME:-azure-westus2-dr}"
dr_cluster_region          = "${DR_CLUSTER_REGION:-westus2}"
availability               = "${KAFKA_AVAILABILITY:-SINGLE_ZONE}"
EOF

print_info "Initializing Terraform..."
terraform init

print_info "Deploying Confluent Cloud clusters with ACLs (this may take 5-10 minutes)..."
print_warning "Note: ACL creation requires your Cloud API key to have OrganizationAdmin role"
print_info "If ACL creation fails, see terraform/confluent-cloud/README.md"

# Try to apply with ACLs
if terraform apply -auto-approve; then
    print_success "Confluent Cloud clusters and ACLs deployed successfully"
else
    print_error "Terraform apply failed"
    print_warning "This is likely due to insufficient Cloud API key permissions"
    print_info "To fix:"
    print_info "  1. Go to: https://confluent.cloud/settings/api-keys"
    print_info "  2. Find your Cloud API key: ${CONFLUENT_CLOUD_API_KEY}"
    print_info "  3. Add role binding: OrganizationAdmin"
    print_info "  4. Run: cd terraform/confluent-cloud && terraform apply"
    print_info "  5. Then resume: ./deploy.sh --skip-terraform"
    exit 1
fi

# Get cluster endpoints and API keys
print_info "Retrieving cluster information..."
PRIMARY_CLUSTER_ENDPOINT=$(terraform output -raw primary_cluster_bootstrap_endpoint | sed 's/SASL_SSL:\/\///')
DR_CLUSTER_ENDPOINT=$(terraform output -raw dr_cluster_bootstrap_endpoint | sed 's/SASL_SSL:\/\///')
PRIMARY_CLUSTER_API_KEY=$(terraform output -raw primary_cluster_api_key)
PRIMARY_CLUSTER_API_SECRET=$(terraform output -raw primary_cluster_api_secret)
DR_CLUSTER_API_KEY=$(terraform output -raw dr_cluster_api_key)
DR_CLUSTER_API_SECRET=$(terraform output -raw dr_cluster_api_secret)
PRIMARY_SERVICE_ACCOUNT_ID=$(terraform output -raw primary_service_account_id)
DR_SERVICE_ACCOUNT_ID=$(terraform output -raw dr_service_account_id)
CC_SCHEMA_REGISTRY_ENDPOINT=$(terraform output -raw schema_registry_endpoint)
CC_SCHEMA_REGISTRY_API_KEY=$(terraform output -raw schema_registry_api_key)
CC_SCHEMA_REGISTRY_API_SECRET=$(terraform output -raw schema_registry_api_secret)

print_success "Cluster and Schema Registry information retrieved"

cd ../..

# -----------------------------------------------------------------------------
# Step 4-6: Create All Certificates and Secrets using Makefile
# -----------------------------------------------------------------------------

print_header "Steps 4-6: Creating Certificates and Secrets"

# Update .env with cluster information from Terraform
print_info "Updating .env file with cluster information..."

# Remove old entries if they exist
grep -v "^PRIMARY_CLUSTER_ENDPOINT=" .env > .env.tmp 2>/dev/null || cp .env .env.tmp
grep -v "^DR_CLUSTER_ENDPOINT=" .env.tmp > .env.tmp2 2>/dev/null || cp .env.tmp .env.tmp2
grep -v "^PRIMARY_CLUSTER_API_KEY=" .env.tmp2 > .env.tmp3 2>/dev/null || cp .env.tmp2 .env.tmp3
grep -v "^PRIMARY_CLUSTER_API_SECRET=" .env.tmp3 > .env.tmp4 2>/dev/null || cp .env.tmp3 .env.tmp4
grep -v "^DR_CLUSTER_API_KEY=" .env.tmp4 > .env.tmp5 2>/dev/null || cp .env.tmp4 .env.tmp5
grep -v "^DR_CLUSTER_API_SECRET=" .env.tmp5 > .env.tmp6 2>/dev/null || cp .env.tmp5 .env.tmp6
grep -v "^PRIMARY_SERVICE_ACCOUNT_ID=" .env.tmp6 > .env.tmp7 2>/dev/null || cp .env.tmp6 .env.tmp7
grep -v "^DR_SERVICE_ACCOUNT_ID=" .env.tmp7 > .env.tmp8 2>/dev/null || cp .env.tmp7 .env.tmp8
grep -v "^SCHEMA_REGISTRY_ENDPOINT=" .env.tmp8 > .env.tmp9 2>/dev/null || cp .env.tmp8 .env.tmp9
grep -v "^SCHEMA_REGISTRY_API_KEY=" .env.tmp9 > .env.tmp10 2>/dev/null || cp .env.tmp9 .env.tmp10
grep -v "^SCHEMA_REGISTRY_API_SECRET=" .env.tmp10 > .env.tmp11 2>/dev/null || cp .env.tmp10 .env.tmp11
grep -v "^CC_SCHEMA_REGISTRY_ENDPOINT=" .env.tmp11 > .env.tmp12 2>/dev/null || cp .env.tmp11 .env.tmp12
grep -v "^CC_SCHEMA_REGISTRY_API_KEY=" .env.tmp12 > .env.tmp13 2>/dev/null || cp .env.tmp12 .env.tmp13
grep -v "^CC_SCHEMA_REGISTRY_API_SECRET=" .env.tmp13 > .env 2>/dev/null || cp .env.tmp13 .env
rm -f .env.tmp .env.tmp2 .env.tmp3 .env.tmp4 .env.tmp5 .env.tmp6 .env.tmp7 .env.tmp8 .env.tmp9 .env.tmp10 .env.tmp11 .env.tmp12 .env.tmp13

# Append new values
cat >> .env <<EOF

# Auto-populated from Terraform (terraform/confluent-cloud/)
PRIMARY_CLUSTER_ENDPOINT=${PRIMARY_CLUSTER_ENDPOINT}
DR_CLUSTER_ENDPOINT=${DR_CLUSTER_ENDPOINT}
PRIMARY_CLUSTER_API_KEY=${PRIMARY_CLUSTER_API_KEY}
PRIMARY_CLUSTER_API_SECRET=${PRIMARY_CLUSTER_API_SECRET}
DR_CLUSTER_API_KEY=${DR_CLUSTER_API_KEY}
DR_CLUSTER_API_SECRET=${DR_CLUSTER_API_SECRET}
PRIMARY_SERVICE_ACCOUNT_ID=${PRIMARY_SERVICE_ACCOUNT_ID}
DR_SERVICE_ACCOUNT_ID=${DR_SERVICE_ACCOUNT_ID}
CC_SCHEMA_REGISTRY_ENDPOINT=${CC_SCHEMA_REGISTRY_ENDPOINT}
CC_SCHEMA_REGISTRY_API_KEY=${CC_SCHEMA_REGISTRY_API_KEY}
CC_SCHEMA_REGISTRY_API_SECRET=${CC_SCHEMA_REGISTRY_API_SECRET}
EOF

print_success ".env file updated with cluster credentials"

print_info "Using Makefile to automate certificate creation..."
print_info "This will:"
echo "  - Download and convert Confluent Cloud certificates"
echo "  - Generate gateway TLS certificates"
echo "  - Create client configuration files"
echo "  - Create all Kubernetes secrets"
echo ""

# Run make to create all certificates and secrets
make certs
make k8s-secrets

print_success "All certificates and secrets created successfully"

# Verify certificates
print_info "Verifying certificates..."
make verify-certs

# -----------------------------------------------------------------------------
# Step 7: Update and Deploy Gateway Configuration
# -----------------------------------------------------------------------------

print_header "Step 7: Deploying Confluent Gateway"

# Update gateway.yaml with actual cluster endpoints
print_info "Updating gateway configuration with cluster endpoints..."

# Backup the original file
cp kubernetes-resources/gateway.yaml kubernetes-resources/gateway.yaml.bak

# Use awk to update endpoints reliably (works on both GNU and BSD)
awk -v primary="${PRIMARY_CLUSTER_ENDPOINT}" -v dr="${DR_CLUSTER_ENDPOINT}" '
  /id: CC_PRIMARY/ { in_primary=1 }
  /id: CC_DR/ { in_primary=0; in_dr=1 }
  /id:/ && !/id: CC_PRIMARY/ && !/id: CC_DR/ { in_primary=0; in_dr=0 }

  /endpoint:/ && in_primary {
    gsub(/endpoint: .*/, "endpoint: " primary)
    in_primary=0
  }
  /endpoint:/ && in_dr {
    gsub(/endpoint: .*/, "endpoint: " dr)
    in_dr=0
  }
  { print }
' kubernetes-resources/gateway.yaml > kubernetes-resources/gateway.yaml.tmp

# Replace original with updated file
mv kubernetes-resources/gateway.yaml.tmp kubernetes-resources/gateway.yaml

print_success "Gateway configuration updated with cluster endpoints:"
print_info "  - Primary Cluster: ${PRIMARY_CLUSTER_ENDPOINT}"
print_info "  - DR Cluster: ${DR_CLUSTER_ENDPOINT}"

print_info "Deploying gateway..."
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent

print_info "Waiting for gateway to be ready..."
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=600s -n confluent

print_success "Gateway deployed successfully"

# -----------------------------------------------------------------------------
# Step 7.5: Update Azure Private DNS A Record
# -----------------------------------------------------------------------------

print_header "Step 7.5: Updating Azure Private DNS"

# Get LoadBalancer IP
print_info "Waiting for LoadBalancer to be provisioned..."
sleep 30  # Wait for LB to be provisioned

LB_IP=$(kubectl get svc confluent-gateway-bootstrap-lb -n confluent \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$LB_IP" ]; then
    print_warning "LoadBalancer IP not available yet."
    print_info "You can update the DNS record manually later with:"
    print_info "  az network private-dns record-set a add-record \\"
    print_info "    --resource-group ${RESOURCE_GROUP_NAME} \\"
    print_info "    --zone-name ${DNS_ZONE_NAME:-axa.com} \\"
    print_info "    --record-set-name ${GATEWAY_DNS_RECORD_NAME:-kafka.cc} \\"
    print_info "    --ipv4-address <LOADBALANCER_IP>"
else
    print_success "LoadBalancer IP: ${LB_IP}"

    # Delete CNAME record if it exists and create A record
    print_info "Updating Azure Private DNS A record..."

    # Delete CNAME record if it exists (from old configuration)
    az network private-dns record-set cname delete \
        --resource-group ${RESOURCE_GROUP_NAME} \
        --zone-name ${DNS_ZONE_NAME:-axa.com} \
        --name ${GATEWAY_DNS_RECORD_NAME:-kafka.cc} \
        --yes 2>/dev/null || true

    # Create A record if it doesn't exist
    az network private-dns record-set a create \
        --resource-group ${RESOURCE_GROUP_NAME} \
        --zone-name ${DNS_ZONE_NAME:-axa.com} \
        --name ${GATEWAY_DNS_RECORD_NAME:-kafka.cc} \
        --ttl 300 2>/dev/null || true

    # Add the IP address to the A record
    az network private-dns record-set a add-record \
        --resource-group ${RESOURCE_GROUP_NAME} \
        --zone-name ${DNS_ZONE_NAME:-axa.com} \
        --record-set-name ${GATEWAY_DNS_RECORD_NAME:-kafka.cc} \
        --ipv4-address "${LB_IP}" || {
        print_warning "Failed to update DNS record automatically"
        print_info "You may need to update it manually"
    }

    print_success "DNS A record updated: ${GATEWAY_DNS_RECORD_NAME:-kafka.cc}.${DNS_ZONE_NAME:-axa.com} -> ${LB_IP}"

    # Verify DNS record
    print_info "Verifying DNS record..."
    az network private-dns record-set a show \
        --resource-group ${RESOURCE_GROUP_NAME} \
        --zone-name ${DNS_ZONE_NAME:-axa.com} \
        --name ${GATEWAY_DNS_RECORD_NAME:-kafka.cc} || true
fi

# -----------------------------------------------------------------------------
# Step 8: Deploy Kafka Tools Pod
# -----------------------------------------------------------------------------

print_header "Step 8: Deploying Kafka Tools Pod"

if [ -n "$LB_IP" ]; then
    print_info "LoadBalancer IP: ${LB_IP}"

    # Auto-update kafka-tools.yaml with the LoadBalancer IP
    print_info "Updating kafka-tools.yaml with LoadBalancer IP..."
    sed -i.bak "s/\(- ip: \)\"[^\"]*\"/\1\"${LB_IP}\"/" kubernetes-resources/kafka-tools.yaml
    rm -f kubernetes-resources/kafka-tools.yaml.bak
fi

print_info "Deploying kafka-tools pod..."
kubectl apply -f kubernetes-resources/kafka-tools.yaml -n confluent

kubectl wait --for=condition=Ready pod/kafka-tools --timeout=120s -n confluent

print_success "Kafka tools pod deployed successfully"

# -----------------------------------------------------------------------------
# Deployment Complete
# -----------------------------------------------------------------------------

print_header "Deployment Complete!"

print_success "All resources have been deployed successfully!"
echo ""
print_info "Summary:"
echo "  - AKS Cluster: ${AKS_CLUSTER_NAME} (${AZURE_LOCATION})"
echo "  - Resource Group: ${RESOURCE_GROUP_NAME}"
echo "  - Primary Kafka Cluster (Azure ${PRIMARY_CLUSTER_REGION}): ${PRIMARY_CLUSTER_ENDPOINT}"
echo "    • Service Account: ${PRIMARY_SERVICE_ACCOUNT_ID}"
echo "    • API Key: ${PRIMARY_CLUSTER_API_KEY}"
echo "  - DR Kafka Cluster (Azure ${DR_CLUSTER_REGION}): ${DR_CLUSTER_ENDPOINT}"
echo "    • Service Account: ${DR_SERVICE_ACCOUNT_ID}"
echo "    • API Key: ${DR_CLUSTER_API_KEY}"
echo "  - Schema Registry (Advanced, Public): ${CC_SCHEMA_REGISTRY_ENDPOINT}"
echo "    • API Key: ${CC_SCHEMA_REGISTRY_API_KEY}"
echo "  - Gateway Domain: ${GATEWAY_DOMAIN}"
echo "  - LoadBalancer IP: ${LB_IP}"
echo ""
print_success "ACLs and Permissions:"
echo "  ✓ Role bindings created (CloudClusterAdmin)"
echo "  ✓ ACLs created (CREATE, WRITE, READ, DESCRIBE for topics)"
echo "  ✓ Consumer group permissions granted"
echo ""
print_info "Next Steps:"
echo ""
echo "  1. Verify Azure Private DNS record: ${GATEWAY_DOMAIN} -> ${LB_IP}"
echo ""
echo "  2. Test topic listing:"
echo "     kubectl exec kafka-tools -n confluent -- kafka-topics \\"
echo "       --bootstrap-server ${GATEWAY_DOMAIN}:9092 \\"
echo "       --command-config /etc/kafka/client-primary/client-primary.properties \\"
echo "       --list"
echo ""
echo "  3. Test message production:"
echo "     kubectl exec kafka-tools -n confluent -- bash -c 'echo -e \"test 1\\ntest 2\\ntest 3\" | kafka-console-producer \\"
echo "       --bootstrap-server ${GATEWAY_DOMAIN}:9092 \\"
echo "       --producer.config /etc/kafka/client-primary/client-primary.properties \\"
echo "       --topic test_topic'"
echo ""
echo "  4. To switch between clusters, update kubernetes-resources/gateway.yaml"
echo "     and run: kubectl apply -f kubernetes-resources/gateway.yaml -n confluent"
echo ""
print_info "Credentials saved to: .env"
print_info "For more details, see README.md"
echo ""
