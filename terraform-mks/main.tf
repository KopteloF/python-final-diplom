# ─────────────────────────────────────────────────────────────────────────────
# Фаза 6: Managed Service for Kubernetes (управляемый кластер YC).
# Смысл фазы: сравнить с self-hosted k3s. Здесь control-plane и его апгрейды —
# на стороне YC; мы описываем только сеть, права SA, SG, версию и node group.
# Kubeconfig берётся напрямую (yc ... get-credentials) → деплой идёт с ноутбука
# без SSH/Ansible, в отличие от self-hosted (terraform/ + deploy/).
# ─────────────────────────────────────────────────────────────────────────────

resource "yandex_vpc_network" "net" {
  name = "mks-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "mks-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.20.0.0/24"]
}

# ── Один SA и для кластера, и для нод (для демо достаточно) ──────────────────
resource "yandex_iam_service_account" "mks" {
  name        = "mks-sa"
  description = "Managed k8s: cluster agent + node group"
}

# Роли выдаём как _member (НЕ _binding): _binding перезатирает всех участников
# роли в папке, а _member добавляет только наш SA. Для демо-папки безопаснее.
locals {
  mks_roles = [
    "k8s.clusters.agent",              # управление кластером
    "k8s.tunnelClusters.agent",        # tunnel-режим сети
    "vpc.publicAdmin",                 # публичные адреса нод/мастера
    "load-balancer.admin",             # Service type=LoadBalancer → YC NLB
    "container-registry.images.puller" # тянуть образы (на будущее)
  ]
}

resource "yandex_resourcemanager_folder_iam_member" "mks" {
  for_each  = toset(local.mks_roles)
  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.mks.id}"
}

# ── Security group по требованиям MKS (свёрнуто в одну группу) ────────────────
# Правила из офиц. доки: health-check'и LB, master↔node (self), pod/service CIDR,
# ICMP из приватных сетей, API 443/6443, NodePort'ы, SSH, egress наружу.
resource "yandex_vpc_security_group" "k8s" {
  name       = "mks-sg"
  network_id = yandex_vpc_network.net.id

  ingress {
    description       = "LB health checks"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description       = "master <-> node, node <-> node"
    protocol          = "ANY"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description    = "pods/services CIDR"
    protocol       = "ANY"
    v4_cidr_blocks = [var.cluster_ipv4_range, var.service_ipv4_range]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    description    = "ICMP из приватных сетей"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description    = "Kubernetes API (443)"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    description    = "Kubernetes API (6443)"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  ingress {
    description    = "NodePort range"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  ingress {
    description    = "SSH к нодам"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    description    = "весь исходящий (образы, NTP, metric-server и т.п.)"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ── Zonal-кластер (control-plane управляет YC) ────────────────────────────────
resource "yandex_kubernetes_cluster" "this" {
  name       = "orders-mks"
  network_id = yandex_vpc_network.net.id

  cluster_ipv4_range = var.cluster_ipv4_range
  service_ipv4_range = var.service_ipv4_range

  master {
    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.subnet.id
    }
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.k8s.id]
  }

  service_account_id      = yandex_iam_service_account.mks.id
  node_service_account_id = yandex_iam_service_account.mks.id
  release_channel         = "REGULAR"

  # Роли должны существовать ДО создания кластера и удаляться ПОСЛЕ него,
  # иначе YC не сможет корректно снести кластер/ноды при destroy.
  depends_on = [yandex_resourcemanager_folder_iam_member.mks]
}

# ── Node group: preemptible, минимальная нода под демо ───────────────────────
resource "yandex_kubernetes_node_group" "this" {
  name       = "orders-ng"
  cluster_id = yandex_kubernetes_cluster.this.id

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.subnet.id]
      security_group_ids = [yandex_vpc_security_group.k8s.id]
    }

    resources {
      cores  = var.node_cores
      memory = var.node_memory_gb
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    scheduling_policy {
      preemptible = true
    }

    container_runtime {
      type = "containerd"
    }
  }
}
