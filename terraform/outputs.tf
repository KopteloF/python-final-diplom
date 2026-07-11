output "vm_external_ip" {
  value = yandex_compute_instance.vm.network_interface.0.nat_ip_address
}

output "kms_key_id" {
  value = yandex_kms_symmetric_key.vault.id
}
