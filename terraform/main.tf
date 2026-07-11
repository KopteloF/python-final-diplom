data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_vpc_network" "net" {
  name = "tf-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "tf-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}

resource "yandex_vpc_security_group" "sg" {
  name       = "tf-sg"
  network_id = yandex_vpc_network.net.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "app http (NodePort/debug)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 8000
  }

  ingress {
    protocol       = "TCP"
    description    = "http (ingress/traefik)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "https (ingress/traefik)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_compute_instance" "vm" {
  name        = "tf-vm-1"
  platform_id = "standard-v3"
  zone        = var.zone

  # Привязываем SA к VM: поды на ноде смогут получить IAM-токен из metadata
  # (169.254.169.254) и дёргать YC KMS без статичного ключа в кластере.
  service_account_id = yandex_iam_service_account.vault_kms.id

  scheduling_policy {
    preemptible = true
  }

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_pubkey_file)}"
  }
}
