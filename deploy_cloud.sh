#!/usr/bin/env bash
# Одна команда: Terraform поднимает облачную VM (YC) -> Ansible накатывает приложение.
# Секреты генерируются случайно (лаба); в проде — из хранилища секретов.
set -euo pipefail
cd "$(dirname "$0")"; ROOT="$(pwd)"

KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
: "${DB_PASSWORD:=$(openssl rand -hex 16)}"
: "${SECRET_KEY:=$(openssl rand -hex 32)}"

echo "== 1/4 Terraform apply =="
cd "$ROOT/terraform"
terraform init -input=false >/dev/null
terraform apply -auto-approve
IP="$(terraform output -raw vm_external_ip)"
echo "   VM external IP: $IP"

echo "== 2/4 Ждём готовности SSH ($IP) =="
for i in $(seq 1 40); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY" "ubuntu@$IP" true 2>/dev/null; then
    echo "   SSH готов"; break
  fi
  echo "   ...ждём ($i)"; sleep 5
done

echo "== 3/4 Генерируем inventory =="
cat > "$ROOT/deploy/inventory_cloud.ini" <<INV
[web]
app_server ansible_host=$IP ansible_user=ubuntu ansible_ssh_private_key_file=$KEY
INV

echo "== 4/4 Ansible деплой =="
cd "$ROOT/deploy"
ansible-playbook -i inventory_cloud.ini deploy.yml \
  --extra-vars "secret_key=$SECRET_KEY db_password=$DB_PASSWORD allowed_hosts=$IP,localhost,127.0.0.1"

echo
echo "=== ГОТОВО: http://$IP:8000/shops ==="
echo "Снести всё:  cd terraform && terraform destroy -auto-approve"
