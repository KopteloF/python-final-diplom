#!/usr/bin/env bash
# Фаза 3 «одной кнопкой»: Terraform (VM + KMS-ключ + SA на VM) -> Ansible (k3s + Vault prod
# + auto-unseal через YC KMS). В финале — демо: убиваем под Vault и он сам распечатывается.
set -euo pipefail
cd "$(dirname "$0")"; ROOT="$(pwd)"

KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

echo "== 1/5 Terraform apply =="
cd "$ROOT/terraform"
terraform init -input=false >/dev/null
terraform apply -auto-approve
IP="$(terraform output -raw vm_external_ip)"
KMS_KEY_ID="$(terraform output -raw kms_key_id)"
echo "   VM external IP: $IP"
echo "   KMS key:        $KMS_KEY_ID"

echo "== 2/5 Ждём готовности SSH ($IP) =="
for i in $(seq 1 40); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY" "ubuntu@$IP" true 2>/dev/null; then
    echo "   SSH готов"; break
  fi
  echo "   ...ждём ($i)"; sleep 5
done

echo "== 3/5 Генерируем inventory =="
cat > "$ROOT/deploy/inventory_cloud.ini" <<INV
[web]
app_server ansible_host=$IP ansible_user=ubuntu ansible_ssh_private_key_file=$KEY
INV

echo "== 4/5 Ansible: k3s + Vault + auto-unseal (KMS) =="
cd "$ROOT/deploy"
ansible-playbook -i inventory_cloud.ini deploy_vault.yml \
  --extra-vars "kms_key_id=$KMS_KEY_ID"

echo
echo "== 5/5 ДЕМО auto-unseal: убиваем под Vault и смотрим, как он сам распечатывается =="
ssh -o StrictHostKeyChecking=no -i "$KEY" "ubuntu@$IP" 'bash -s' <<'REMOTE'
set -e
K="sudo k3s kubectl -n vault"
echo "-- до рестарта:"; $K exec vault-0 -c vault -- vault status | grep -E 'Sealed|Initialized' || true
echo "-- удаляю под vault-0..."; $K delete pod vault-0 >/dev/null
$K rollout status statefulset/vault --timeout=240s >/dev/null
echo "-- сразу после старта (ожидаем Sealed=true пару секунд):"
$K exec vault-0 -c vault -- vault status | grep -E 'Sealed' || true
echo "-- ждём sidecar (auto-unseal через KMS)..."
for i in $(seq 1 30); do
  S=$($K exec vault-0 -c vault -- vault status -format=json 2>/dev/null | jq -r .sealed 2>/dev/null || echo pending)
  if [ "$S" = "false" ]; then echo "   Sealed=false — Vault распечатан САМ, руками ничего не вводили"; break; fi
  sleep 5
done
echo "-- логи sidecar:"; $K logs vault-0 -c unseal-agent --tail=6 || true
REMOTE

echo
echo "=== ГОТОВО. Vault в облаке с auto-unseal через YC KMS. ==="
echo "Снести всё:  cd terraform && terraform destroy -auto-approve"
