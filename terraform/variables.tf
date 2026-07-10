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

variable "ssh_pubkey_file" {
  type    = string
  default = "/home/controlnode/.ssh/id_rsa.pub"
}
