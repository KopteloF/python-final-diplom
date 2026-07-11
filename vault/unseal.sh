#!/usr/bin/env bash
# Распечатывает Vault после рестарта/ребута.
# Ключи берёт из ~/vault-init.txt (лежит ВНЕ git). Порог 3 из 5.
set -euo pipefail
POD="${1:-vault-0}"; NS="${2:-vault}"
for k in $(grep 'Unseal Key' ~/vault-init.txt | awk '{print $NF}' | head -3); do
  kubectl -n "$NS" exec "$POD" -- vault operator unseal "$k" >/dev/null
done
kubectl -n "$NS" exec "$POD" -- vault status | grep -E "Initialized|Sealed|HA Mode"
