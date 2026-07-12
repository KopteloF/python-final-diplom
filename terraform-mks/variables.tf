variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

variable "sa_key_file" {
  type    = string
  default = "/home/controlnode/yc-key.json"
}

# Диапазоны кластера/сервисов; на них же завязаны правила SG.
variable "cluster_ipv4_range" {
  type    = string
  default = "10.96.0.0/16"
}

variable "service_ipv4_range" {
  type    = string
  default = "10.112.0.0/16"
}

# Размер ноды. Preemptible + network-hdd — минимальная цена под короткую демо-сессию.
variable "node_cores" {
  type    = number
  default = 2
}

variable "node_memory_gb" {
  type    = number
  default = 4
}

variable "node_count" {
  type    = number
  default = 1
}
