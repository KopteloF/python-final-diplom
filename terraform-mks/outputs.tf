output "cluster_id" {
  value = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.this.name
}

# Публичный endpoint мастера (для справки; kubeconfig берём через yc get-credentials).
output "cluster_external_endpoint" {
  value = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}
