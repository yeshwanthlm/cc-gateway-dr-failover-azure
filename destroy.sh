#!/bin/bash

# =============================================================================
# Confluent Cloud Gateway Demo - Destruction Script (Azure)
# =============================================================================
# This script automates the complete destruction of:
# - Kubernetes resources (Gateway, Secrets, Pods)
# - Confluent Operator (Helm)
# - Confluent Cloud Kafka Clusters (Standard Primary + Dedicated DR)
# - Cluster Linking and Mirror Topics
# - Schema Registry
# - Azure AKS Cluster and VNet
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

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------

print_header "Confluent Cloud Gateway Demo - Destruction"

print_warning "This will destroy ALL resources including:"
echo "  - Kubernetes Gateway and resources"
echo "  - Confluent Operator (Helm)"
echo "  - Confluent Cloud Kafka Clusters:"
echo "      • Primary (Standard) in East US"
echo "      • DR (Dedicated, 1 CKU) in West US 2"
echo "  - Cluster Linking (Primary → DR)"
echo "  - Mirror Topics (test_topic)"
echo "  - Schema Registry (Advanced package)"
echo "  - Azure AKS Cluster and VNet"
echo "  - Azure Resource Group (if empty)"
echo ""
print_error "This action cannot be undone!"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
echo

if [[ ! $REPLY =~ ^yes$ ]]; then
    print_info "Destruction cancelled."
    exit 0
fi

# Load environment variables if .env exists
if [ -f .env ]; then
    print_info "Loading configuration from .env file..."
    export $(cat .env | grep -v '^#' | xargs)
fi

# -----------------------------------------------------------------------------
# Step 1: Delete Kubernetes Resources
# -----------------------------------------------------------------------------

print_header "Step 1: Deleting Kubernetes Resources"

# Check if kubectl is configured
if kubectl cluster-info &> /dev/null; then
    print_info "Kubernetes cluster is accessible"

    # Delete gateway
    if kubectl get namespace confluent &> /dev/null; then
        print_info "Deleting gateway resource..."
        kubectl delete -f kubernetes-resources/gateway.yaml -n confluent 2>&1 || print_warning "Gateway already deleted or not found"

        # Delete kafka-tools pod
        print_info "Deleting kafka-tools pod..."
        kubectl delete -f kubernetes-resources/kafka-tools.yaml -n confluent 2>&1 || print_warning "Kafka-tools already deleted or not found"

        # Delete secrets
        print_info "Deleting secrets..."
        kubectl delete secret -n confluent \
            cc-primary-tls \
            cc-dr-tls \
            gateway-tls \
            gateway-truststore \
            client-primary \
            client-dr \
            2>&1 || print_warning "Some secrets already deleted or not found"

        print_success "Kubernetes resources deleted"
    else
        print_warning "Confluent namespace not found, skipping Kubernetes resources cleanup"
    fi
else
    print_warning "Kubernetes cluster not accessible, skipping Kubernetes resources cleanup"
fi

# -----------------------------------------------------------------------------
# Step 2: Uninstall Confluent Operator
# -----------------------------------------------------------------------------

print_header "Step 2: Uninstalling Confluent Operator"

if kubectl get namespace confluent &> /dev/null; then
    # Check if helm release exists
    if helm list -n confluent | grep -q confluent-operator; then
        print_info "Uninstalling Confluent operator..."
        helm uninstall confluent-operator -n confluent
        print_success "Confluent operator uninstalled"
    else
        print_warning "Confluent operator not found"
    fi

    # Delete namespace
    print_info "Deleting confluent namespace..."
    kubectl delete namespace confluent
    print_success "Confluent namespace deleted"
else
    print_warning "Confluent namespace not found, skipping operator cleanup"
fi

# -----------------------------------------------------------------------------
# Step 3: Destroy Confluent Cloud Resources
# -----------------------------------------------------------------------------

print_header "Step 3: Destroying Confluent Cloud Resources"

if [ -d "terraform/confluent-cloud" ]; then
    cd terraform/confluent-cloud

    # Check if terraform state exists
    if [ -f "terraform.tfstate" ]; then
        print_info "Destroying Confluent Cloud clusters..."
        terraform destroy -auto-approve
        print_success "Confluent Cloud resources destroyed"
    else
        print_warning "No Confluent Cloud terraform state found, skipping"
    fi

    cd ../..
else
    print_warning "terraform/confluent-cloud directory not found, skipping"
fi

# -----------------------------------------------------------------------------
# Step 4: Destroy Azure AKS Cluster
# -----------------------------------------------------------------------------

print_header "Step 4: Destroying Azure AKS Cluster"

if [ -d "terraform/aks" ]; then
    cd terraform/aks

    # Check if terraform state exists
    if [ -f "terraform.tfstate" ]; then
        print_info "Destroying AKS cluster and VNet (this may take 10-15 minutes)..."
        terraform destroy -auto-approve
        print_success "AKS cluster and VNet destroyed"
    else
        print_warning "No AKS terraform state found, skipping"
    fi

    cd ../..
else
    print_warning "terraform/aks directory not found, skipping"
fi

# -----------------------------------------------------------------------------
# Step 5: Clean up certificates and temporary files using Makefile
# -----------------------------------------------------------------------------

print_header "Step 5: Cleaning Up Certificates and Temporary Files"

print_info "Using Makefile to clean up certificates..."
make clean-certs 2>/dev/null || {
    print_warning "Makefile cleanup failed, performing manual cleanup..."
    rm -f /tmp/cc-primary-truststore.jks
    rm -f /tmp/cc-dr-truststore.jks
    rm -f /tmp/gateway-truststore.jks
    rm -f /tmp/jksPassword.txt
    rm -f /tmp/gateway-ca.pem
    rm -rf certs/ssl/*
    rm -rf gateway-tls-cert/*.pem gateway-tls-cert/*.csr gateway-tls-cert/*.srl gateway-tls-cert/*.cnf
    rm -f clients/client-primary.properties
    rm -f clients/client-dr.properties
}
print_success "Certificates and temporary files cleaned"

# -----------------------------------------------------------------------------
# Destruction Complete
# -----------------------------------------------------------------------------

print_header "Destruction Complete!"

print_success "All resources have been destroyed successfully!"
echo ""
print_info "Destroyed resources:"
echo "  ✓ Kubernetes Gateway and resources"
echo "  ✓ Confluent Operator (Helm)"
echo "  ✓ Confluent Cloud Kafka Clusters:"
echo "      • Primary (Standard) cluster"
echo "      • DR (Dedicated) cluster"
echo "  ✓ Cluster Linking and Mirror Topics"
echo "  ✓ Schema Registry"
echo "  ✓ Azure AKS Cluster and VNet"
echo "  ✓ Azure Resource Group (if empty)"
echo "  ✓ Temporary files and certificates"
echo ""
print_info "Your .env file and source code remain intact."
print_info "Run ./deploy.sh to deploy again."
echo ""
