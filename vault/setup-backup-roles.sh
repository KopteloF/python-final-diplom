#!/usr/bin/env bash
# Фаза 5: право снимать снапшот Raft для CronJob'а бэкапа Vault.
# Политика least-privilege (только read sys/storage/raft/snapshot) + k8s-роль,
# привязанная к SA vault-backup в ns orders.
# Запуск: VAULT_TOKEN=<root> ./vault/setup-backup-roles.sh
set -euo pipefail

NS_VAULT="${NS_VAULT:-vault}"
POD="${VAULT_POD:-vault-0}"
APP_NS="${APP_NS:-orders}"
TOKEN="${VAULT_TOKEN:-${1:-}}"
[ -n "$TOKEN" ] || { echo "Нужен root-token: VAULT_TOKEN=... $0   (или первым аргументом)"; exit 1; }

echo "== Политика vault-backup (read sys/storage/raft/snapshot) =="
kubectl -n "$NS_VAULT" exec -i "$POD" -- env VAULT_TOKEN="$TOKEN" vault policy write vault-backup - <<'POLICY'
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
POLICY

echo "== Роль k8s-auth vault-backup (SA vault-backup в ns $APP_NS) =="
kubectl -n "$NS_VAULT" exec "$POD" -- env VAULT_TOKEN="$TOKEN" \
  vault write auth/kubernetes/role/vault-backup \
    bound_service_account_names=vault-backup \
    bound_service_account_namespaces="$APP_NS" \
    policies=vault-backup \
    ttl=10m

echo "OK: policy + role vault-backup созданы."
