#!/usr/bin/env bash
# Фаза 4: даём поду Postgres право читать пароль БД из Vault.
# Политика least-privilege (только secret/orders/db) + k8s-роль, привязанная к SA orders-db.
# Запуск (локальный кластер): VAULT_TOKEN=<root> ./vault/setup-orders-db.sh
set -euo pipefail

NS_VAULT="${NS_VAULT:-vault}"
POD="${VAULT_POD:-vault-0}"
APP_NS="${APP_NS:-orders}"
TOKEN="${VAULT_TOKEN:-${1:-}}"
[ -n "$TOKEN" ] || { echo "Нужен root-token: VAULT_TOKEN=... $0   (или первым аргументом)"; exit 1; }

echo "== Политика orders-db (read secret/orders/db) =="
kubectl -n "$NS_VAULT" exec -i "$POD" -- env VAULT_TOKEN="$TOKEN" vault policy write orders-db - <<'POLICY'
path "secret/data/orders/db" {
  capabilities = ["read"]
}
POLICY

echo "== Роль k8s-auth orders-db (SA orders-db в ns $APP_NS) =="
kubectl -n "$NS_VAULT" exec "$POD" -- env VAULT_TOKEN="$TOKEN" \
  vault write auth/kubernetes/role/orders-db \
    bound_service_account_names=orders-db \
    bound_service_account_namespaces="$APP_NS" \
    policies=orders-db \
    ttl=1h

echo "OK: policy + role orders-db созданы. Теперь helm upgrade поднимет Postgres с инъекцией Vault."
