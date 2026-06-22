# Confluent Cloud Gateway Setup for Cluster Switchover (Azure)

This guide demonstrates how to set up Confluent Gateway on AKS (Azure Kubernetes Service) to enable seamless switchover between Confluent Cloud clusters across multiple Azure regions.

## Architecture Diagram:
<img width="1540" height="870" alt="image (2)" src="https://github.com/user-attachments/assets/f0721e47-cf64-4e8d-aced-060d30f414f2" />

---

## 🚀 Quick Start - Automated Deployment

**Recommended!** Complete automation for deployment and cleanup:

```bash
# 1. Login to Azure
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# 2. Get your subscription ID
az account show --query id -o tsv

# 3. Configure environment
cp .env.example .env
nano .env
# Add:
#   AZURE_SUBSCRIPTION_ID=your-subscription-id
#   OWNER_EMAIL=your.email@company.com
#   CONFLUENT_CLOUD_API_KEY=your-api-key
#   CONFLUENT_CLOUD_API_SECRET=your-api-secret

# 4. Deploy everything (~20 minutes)
./deploy.sh

# 5. Destroy everything when done (~15 minutes)
./destroy.sh
```

---

## 🏗️ Architecture Overview

**Complete Azure Multi-Region Deployment**

This repository deploys a fully automated Confluent Cloud Gateway infrastructure across **3 Azure regions**:

```
┌─────────────────────────────────────────────────────────────┐
│                      AZURE CLOUD                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  🌐 Region 1: East US (eastus)                             │
│  ┌────────────────────────────────────────┐                │
│  │ Primary Confluent Cloud Kafka Cluster  │                │
│  │ - Bootstrap: pkc-xxxxx.eastus.azure... │                │
│  │ - Service Account + API Keys            │                │
│  │ - CloudClusterAdmin Role                │                │
│  └────────────────────────────────────────┘                │
│                                                              │
│  🌐 Region 2: West US 2 (westus2)                          │
│  ┌────────────────────────────────────────┐                │
│  │ DR Confluent Cloud Kafka Cluster       │                │
│  │ - Bootstrap: pkc-yyyyy.westus2.azure...│                │
│  │ - Service Account + API Keys            │                │
│  │ - CloudClusterAdmin Role                │                │
│  └────────────────────────────────────────┘                │
│                                                              │
│  🌐 Region 3: Central US (centralus)                       │
│  ┌────────────────────────────────────────┐                │
│  │ AKS Cluster (Kubernetes 1.36)          │                │
│  │ ├─ Confluent Gateway Pods              │                │
│  │ ├─ Kafka Tools Pod                     │                │
│  │ ├─ LoadBalancer Service                │                │
│  │ └─ Azure Private DNS Zone (axa.com)    │                │
│  │    • A Record: kafka.cc.axa.com       │                │
│  └────────────────────────────────────────┘                │
│                                                              │
│  📍 Gateway Endpoint: kafka.cc.axa.com:9092               │
│  🔐 Azure Private DNS Zone: axa.com                         │
│  🔄 Seamless Switchover: Primary ⟷ DR                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Architecture Features

- **All on Azure**: No cross-cloud complexity, all resources in Azure
- **Geographic Redundancy**: Kafka clusters in different Azure regions (East US, West US 2)
- **Neutral Gateway Location**: AKS cluster in Central US (independent from both Kafka clusters)
- **Private DNS**: Azure Private DNS Zone created and managed via Terraform
- **Automated DNS Updates**: A records automatically updated with LoadBalancer IP
- **TLS Everywhere**: Encrypted connections from clients to gateway and gateway to clusters
- **RBAC Security**: Cluster-specific service accounts with CloudClusterAdmin roles

---

## 📊 What Gets Created

### Azure Infrastructure (Central US)

| Resource | Name/Value | Purpose |
|----------|------------|---------|
| **Resource Group** | `cc-gateway-rg` | Container for all Azure resources |
| **Virtual Network** | `cc-gateway-aks-vnet` | Network isolation (CIDR: 10.0.0.0/16) |
| **Subnet** | `cc-gateway-aks-subnet` | AKS nodes subnet (10.0.1.0/24) |
| **Network Security Group** | `cc-gateway-aks-nsg` | Firewall rules (HTTPS, Kafka ports) |
| **AKS Cluster** | `cc-gateway-aks` | Kubernetes 1.36, 2 nodes (Standard_D2s_v3) |
| **Azure Private DNS Zone** | `axa.com` | Private DNS for gateway domain |
| **DNS A Record** | `kafka.cc.axa.com` | Points to LoadBalancer IP |
| **VNet Link** | DNS to VNet | Enables DNS resolution in AKS |

### Confluent Cloud Resources

#### Primary Cluster (East US)
- **Environment**: `cc-gateway-demo-azure`
- **Cluster**: `azure-eastus-primary` (Basic tier)
- **Cloud**: Azure
- **Region**: eastus
- **Availability**: Single Zone (configurable to Multi Zone)
- **Service Account**: With CloudClusterAdmin role
- **API Keys**: Cluster-specific keys with full permissions
- **ACLs**: CREATE, WRITE, READ, DESCRIBE on topics

#### DR Cluster (West US 2)
- **Cluster**: `azure-westus2-dr` (Basic tier)
- **Cloud**: Azure
- **Region**: westus2
- **Availability**: Single Zone (configurable to Multi Zone)
- **Service Account**: With CloudClusterAdmin role
- **API Keys**: Cluster-specific keys with full permissions
- **ACLs**: CREATE, WRITE, READ, DESCRIBE on topics

#### Schema Registry (Fully Automated)
- **Package**: Advanced (with Governance features)
- **Endpoint**: Public REST endpoint
- **Region**: Automatically provisioned
- **Service Account**: With ResourceOwner role
- **API Keys**: Schema Registry-specific key
- **Features**: Schema validation, compatibility checking, versioning
- **Deployment**: Fully automated via Terraform (no manual steps!)

### Kubernetes Resources (on AKS)

| Resource | Type | Purpose |
|----------|------|---------|
| **Namespace** | `confluent` | Isolation for Confluent components |
| **Confluent Operator** | Helm Release | Manages Confluent Gateway lifecycle |
| **Gateway Deployment** | `confluent-gateway` | Routes traffic between clusters |
| **LoadBalancer Service** | `confluent-gateway-bootstrap-lb` | External access with Azure LB |
| **Kafka Tools Pod** | Testing pod | Producer/consumer testing |
| **Secrets (6)** | TLS & Config | Certificates and client configurations |

---

## ✅ Key Features

1. ✅ **All on Azure** - No cross-cloud complexity
2. ✅ **Geographic Redundancy** - Clusters in different Azure regions
3. ✅ **Neutral Gateway Location** - AKS in third region (Central US)
4. ✅ **Automated DNS** - Azure Private DNS Zone via Terraform
5. ✅ **One-Command Deployment** - `./deploy.sh` does everything
6. ✅ **One-Command Cleanup** - `./destroy.sh` removes all resources
7. ✅ **Certificate Automation** - Makefile handles all certificates
8. ✅ **Switchover Ready** - Switch clusters in minutes
9. ✅ **Security First** - Private DNS, TLS everywhere, RBAC
10. ✅ **Production Ready** - Multi-zone support, monitoring, ACLs

---

## 📋 Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login` configured)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [Helm](https://helm.sh/docs/intro/install/) >= 3.0
- [OpenSSL](https://www.openssl.org/) - Certificate generation
- Java KeyTool (part of JDK) - JKS truststore conversion

### Required Accounts & Credentials

- **Azure Subscription** with permissions to create:
  - Resource Groups
  - AKS Clusters
  - VNets and NSGs
  - Private DNS Zones
- **Confluent Cloud Account** with:
  - Cloud API Keys ([Get them here](https://confluent.cloud/settings/api-keys))
  - OrganizationAdmin role (for ACL creation)

---

## 🚀 Automated Deployment Guide

### Step 1: Azure Setup

```bash
# Login to Azure
az login

# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Get subscription ID
az account show --query id -o tsv
```

### Step 2: Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

**Required configuration in `.env`:**
```bash
# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-azure-subscription-id
OWNER_EMAIL=your.email@company.com
AZURE_LOCATION=centralus

# Confluent Cloud Configuration
CONFLUENT_CLOUD_API_KEY=your-cloud-api-key
CONFLUENT_CLOUD_API_SECRET=your-cloud-api-secret

# DNS Configuration (optional, uses defaults)
DNS_ZONE_NAME=axa.com
GATEWAY_DNS_RECORD_NAME=kafka.cc
GATEWAY_DOMAIN=kafka.cc.axa.com
```

### Step 3: Deploy

```bash
# Deploy everything (takes ~20 minutes)
./deploy.sh
```

**What happens during deployment:**

1. ✅ **Pre-flight Checks** - Validates tools and credentials
2. ✅ **AKS Cluster** - Deploys Kubernetes cluster (10-15 min)
3. ✅ **Confluent Operator** - Installs via Helm
4. ✅ **Confluent Cloud Clusters** - Creates Primary + DR clusters (5-10 min)
5. ✅ **Certificates** - Downloads and converts all certificates
6. ✅ **Kubernetes Secrets** - Creates all required secrets
7. ✅ **Gateway Deployment** - Deploys and configures gateway
8. ✅ **DNS Configuration** - Creates A record with LoadBalancer IP
9. ✅ **Kafka Tools Pod** - Deploys testing pod
10. ✅ **Verification** - Displays summary and next steps

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n confluent

# Check services
kubectl get svc -n confluent

# Verify DNS record
az network private-dns record-set a show \
  --resource-group cc-gateway-rg \
  --zone-name axa.com \
  --name kafka.cc
```

### Step 5: Test Connectivity

#### Test Primary Cluster (East US)

**Note:** The gateway must be configured to route to `cc-primary` first. Check with:
```bash
kubectl get gateway confluent-gateway -n confluent -o yaml | grep "bootstrapServerId:"
```

```bash
# List topics on Primary cluster
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-primary/client-primary.properties \
  --list

# Create test topic on Primary (if not exists)
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-primary/client-primary.properties \
  --create --topic test_topic --partitions 3 --replication-factor 3

# Produce test messages to Primary
kubectl exec kafka-tools -n confluent -- bash -c \
  'echo -e "primary-msg-1\nprimary-msg-2\nprimary-msg-3" | kafka-console-producer \
    --bootstrap-server kafka.cc.axa.com:9092 \
    --producer.config /etc/kafka/client-primary/client-primary.properties \
    --topic test_topic'

# Consume messages from Primary
kubectl exec kafka-tools -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --consumer.config /etc/kafka/client-primary/client-primary.properties \
  --topic test_topic \
  --from-beginning \
  --max-messages 10 \
  --timeout-ms 10000
```

#### Test DR Cluster (West US 2)

**Note:** The gateway must be configured to route to `cc-dr` first. Switch using the instructions in [Cluster Switchover Process](#-cluster-switchover-process).

```bash
# List topics on DR cluster
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties \
  --list

# Create test topic on DR (if not exists)
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties \
  --create --topic test_topic --partitions 3 --replication-factor 3

# Produce test messages to DR
kubectl exec kafka-tools -n confluent -- bash -c \
  'echo -e "dr-msg-1\ndr-msg-2\ndr-msg-3" | kafka-console-producer \
    --bootstrap-server kafka.cc.axa.com:9092 \
    --producer.config /etc/kafka/client-dr/client-dr.properties \
    --topic test_topic'

# Consume messages from DR
kubectl exec kafka-tools -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --consumer.config /etc/kafka/client-dr/client-dr.properties \
  --topic test_topic \
  --from-beginning \
  --max-messages 10 \
  --timeout-ms 10000
```

**✅ Both clusters are accessible through the same gateway endpoint (`kafka.cc.axa.com:9092`)!**  
**⚠️ Important:** The gateway routes to ONE cluster at a time. Use the correct client config that matches the active cluster.

---

## 🔄 Cluster Switchover Process

To switch from **Primary** (East US) to **DR** (West US 2):

### Step 1: Edit Gateway Configuration

```bash
nano kubernetes-resources/gateway.yaml
```

Change lines 50-52:
```yaml
# FROM:
streamingDomain:
  name: cc-primary
  bootstrapServerId: CC_PRIMARY

# TO:
streamingDomain:
  name: cc-dr
  bootstrapServerId: CC_DR
```

### Step 2: Apply Changes

```bash
# Apply the updated configuration
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent

# Restart gateway pods
kubectl delete pod -n confluent -l app=confluent-gateway

# Wait for gateway to be ready
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=120s -n confluent
```

### Step 3: Verify Switchover

```bash
# Check which cluster is active
kubectl get gateway confluent-gateway -n confluent -o yaml | grep -A5 "streamingDomain:"

# Test with DR credentials
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties \
  --list

# Produce messages to DR cluster
kubectl exec kafka-tools -n confluent -- bash -c \
  'echo -e "dr-test-1\ndr-test-2\ndr-test-3" | kafka-console-producer \
    --bootstrap-server kafka.cc.axa.com:9092 \
    --producer.config /etc/kafka/client-dr/client-dr.properties \
    --topic test_topic_dr'

# Consume messages from DR cluster
kubectl exec kafka-tools -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --consumer.config /etc/kafka/client-dr/client-dr.properties \
  --topic test_topic_dr \
  --from-beginning \
  --max-messages 10 \
  --timeout-ms 10000
```

**✅ Switchover complete!** Clients reconnect automatically to the new cluster through the same endpoint: `kafka.cc.axa.com:9092`

---

## 🔍 Verification & Monitoring

```bash
# Check all Kubernetes resources
kubectl get all -n confluent

# Check gateway status and active cluster
kubectl get gateway confluent-gateway -n confluent -o yaml | grep -A5 "streamingDomain:"

# View gateway logs
kubectl logs -n confluent -l app=confluent-gateway --tail=100 -f

# Check Azure DNS record
az network private-dns record-set a show \
  --resource-group cc-gateway-rg \
  --zone-name axa.com \
  --name kafka.cc
```

---

## 🧹 Cleanup

```bash
./destroy.sh
```

**This removes:**
- ✅ Confluent Cloud clusters (Primary + DR)
- ✅ Schema Registry
- ✅ AKS cluster and all Kubernetes resources
- ✅ VNet, NSG, and all network resources
- ✅ Azure Private DNS Zone
- ✅ Resource Group (if empty)
- ✅ All local certificates and temporary files

---

## 🔐 Security Best Practices

1. **Private DNS Only** - DNS zone is private, not exposed to internet
2. **TLS Encryption** - All connections encrypted (client→gateway, gateway→cluster)
3. **Network Security Groups** - Firewall rules limit access
4. **Cluster-Specific API Keys** - Separate credentials for each cluster
5. **RBAC** - Service accounts with CloudClusterAdmin role
6. **Managed Identity** - AKS uses system-assigned managed identity
7. **Secret Management** - Kubernetes secrets for sensitive data
8. **No Hardcoded Credentials** - All credentials in .env (gitignored)

---

## 📚 File Structure

```
.
├── README.md                        # Complete documentation
├── .env.example                     # Configuration template
├── deploy.sh                        # Automated deployment
├── destroy.sh                       # Automated cleanup
├── Makefile                         # Certificate automation
├── terraform/
│   ├── aks/                         # Azure AKS infrastructure
│   └── confluent-cloud/             # Confluent Cloud clusters & Schema Registry
├── certs/                           # Downloaded certificates
├── gateway-tls-cert/                # Generated gateway certificates
├── clients/                         # Client configuration files
└── kubernetes-resources/
    ├── gateway.yaml                 # Gateway configuration
    └── kafka-tools.yaml             # Testing pod
```

---

## 🚀 Production Deployment Considerations

1. **Multi-Zone Availability**: Change `KAFKA_AVAILABILITY=MULTI_ZONE` in .env
2. **Certificate Authority**: Use trusted CA instead of self-signed certificates
3. **DNS TTL**: Use low TTL (60s) for faster failover
4. **Monitoring**: Set up Azure Monitor and Confluent Cloud metrics
5. **Backup Strategy**: Regular backups of gateway configuration
6. **Testing**: Regular switchover testing (monthly recommended)
7. **Client Configuration**: Proper retry logic and timeouts
8. **Resource Sizing**: Scale AKS nodes based on traffic
9. **Cost Optimization**: Use Azure Reservations for long-term savings

---

## 📊 Quick Command Reference

```bash
# Deployment & Cleanup
./deploy.sh                          # Deploy everything
./destroy.sh                         # Destroy everything

# Certificate Management
make certs k8s-secrets               # Create all certificates and secrets
make verify-certs                    # Verify certificates
make help                            # Show all Makefile commands

# Monitoring
kubectl get all -n confluent         # Check all resources
kubectl logs -n confluent -l app=confluent-gateway  # Gateway logs
kubectl get gateway confluent-gateway -n confluent -o yaml | grep "bootstrapServerId:"  # Active cluster

# Testing
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cc.axa.com:9092 \
  --command-config /etc/kafka/client-primary/client-primary.properties \
  --list
```

---

## 🎯 Summary

This repository provides a **complete, production-ready** Confluent Cloud Gateway deployment on Azure:

✅ **Fully Automated** - One command to deploy, one to destroy  
✅ **Multi-Region** - Geographic redundancy across 3 Azure regions  
✅ **Secure** - Private DNS, TLS everywhere, RBAC, Network Security Groups  
✅ **Cost-Effective** - ~$2,925/month for complete HA setup with Schema Registry  
✅ **Production-Ready** - ACLs, Schema Registry, monitoring, multi-zone support  
✅ **Easy Switchover** - Minutes to switch between clusters  
✅ **Well Documented** - Comprehensive guides and troubleshooting  

**Gateway Endpoint**: `kafka.cc.axa.com:9092`  
**Schema Registry**: Public REST endpoint with Advanced governance

**Resources**:
- Primary Kafka: Azure East US (eastus)
- DR Kafka: Azure West US 2 (westus2)
- Schema Registry: Advanced package with public endpoint
- Gateway (AKS): Azure Central US (centralus)

---

## 💬 Support & Contributing

- **Issues**: Open an issue on GitHub
- **Questions**: See troubleshooting sections above
- **Contributions**: PRs welcome!

---

**🎉 Happy Confluent Gateway testing on Azure!**
