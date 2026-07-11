# Фаза 3: KMS-ключ для auto-unseal Vault + сервисный аккаунт, привязанный к VM.
# Идея: unseal-ключи Vault храним ЗАШИФРОВАННЫМИ этим KMS-ключом; unseal-sidecar
# в поде расшифровывает их через YC KMS (авторизуясь IAM-токеном из metadata VM)
# и распечатывает Vault. Ручной unseal не нужен даже после рестарта пода.

resource "yandex_kms_symmetric_key" "vault" {
  name              = "vault-unseal"
  default_algorithm = "AES_256"
  rotation_period   = "8760h" # 1 год
}

# Отдельный SA только для крипто-операций с этим ключом (least privilege).
resource "yandex_iam_service_account" "vault_kms" {
  name        = "vault-kms"
  description = "Auto-unseal Vault через YC KMS (encrypt/decrypt unseal-ключей)"
}

# Право шифровать/расшифровывать ИМЕННО этим ключом (не на всю папку).
resource "yandex_kms_symmetric_key_iam_binding" "vault_encrypt_decrypt" {
  symmetric_key_id = yandex_kms_symmetric_key.vault.id
  role             = "kms.keys.encrypterDecrypter"
  members          = ["serviceAccount:${yandex_iam_service_account.vault_kms.id}"]
}
