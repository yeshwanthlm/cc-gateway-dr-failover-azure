output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for AKS control plane"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure location"
  value       = azurerm_resource_group.main.location
}

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config" {
  description = "Kubeconfig for AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "configure_kubectl" {
  description = "Configure kubectl: run the following command to update your kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = <<-EOT

    ╔════════════════════════════════════════════════════════════════════════════════╗
    ║  Update your kubeconfig with the following command:                           ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║  az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}
    ╚════════════════════════════════════════════════════════════════════════════════╝

  EOT
}

output "dns_zone_name" {
  description = "Azure Private DNS Zone name"
  value       = azurerm_private_dns_zone.gateway.name
}

output "dns_zone_id" {
  description = "Azure Private DNS Zone ID"
  value       = azurerm_private_dns_zone.gateway.id
}

output "gateway_fqdn" {
  description = "Fully qualified domain name for the gateway"
  value       = "${var.gateway_dns_record_name}.${var.dns_zone_name}"
}

output "dns_update_command" {
  description = "Command to update DNS A record after LoadBalancer is created"
  value       = <<-EOT

    ╔════════════════════════════════════════════════════════════════════════════════╗
    ║  After LoadBalancer is created, update the DNS A record:                      ║
    ╠════════════════════════════════════════════════════════════════════════════════╣
    ║  1. Get LoadBalancer IP:                                                       ║
    ║     kubectl get svc confluent-gateway-bootstrap-lb -n confluent \              ║
    ║       -o jsonpath='{.status.loadBalancer.ingress[0].ip}'                       ║
    ║                                                                                 ║
    ║  2. Update DNS A record:                                                       ║
    ║     az network private-dns record-set a add-record \                           ║
    ║       --resource-group ${azurerm_resource_group.main.name} \                                                ║
    ║       --zone-name ${azurerm_private_dns_zone.gateway.name} \                                                     ║
    ║       --record-set-name ${var.gateway_dns_record_name} \                                             ║
    ║       --ipv4-address <LOADBALANCER_IP>                                         ║
    ╚════════════════════════════════════════════════════════════════════════════════╝

  EOT
}
