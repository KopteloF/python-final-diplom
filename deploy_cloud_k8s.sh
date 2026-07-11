#!/usr/bin/env bash
# Одна команда: Terraform поднимает облачную VM (YC) -> Ansible ставит k3s и катит Helm-чарт.
# Секреты генерируются случайно (лаба, Фаза 1); Vault подключим в Фазе 3.
set -euo pipefail
cd "$(dirname "$0")"; ROOT="$(pwd)"

KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
: "${DB_PASSWORD:=$(openssl rand -hex 16)}"
: "${SECRET_KEY:=$(openssl rand -hex 32)}"
IMAGE_TAG="${IMAGE_TAG:-}"   # пусто = взять тег из values.yaml

echo "== 1/4 Terraform apply =="
cd "$ROOT/terraform"
terraform init -input=false >/dev/null
terraform apply -auto-approve
IP="$(terraform output -raw vm_external_ip)"
LE_HOST="${IP}.sslip.io"        # DNS без покупки домена: <ip>.sslip.io -> этот IP
echo "   VM external IP: $IP"
echo "   Хост для TLS:  $LE_HOST"

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

echo "== 4/4 Ansible: k3s + Helm =="
cd "$ROOT/deploy"
ansible-playbook -i inventory_cloud.ini deploy_k3s.yml \
  --extra-vars "secret_key=$SECRET_KEY db_password=$DB_PASSWORD image_tag=$IMAGE_TAG le_host=$LE_HOST"

echo
echo "=== Проверка ==="
sleep 5
curl -s -o /dev/null -w "  http://$LE_HOST/shops   -> HTTP %{http_code}\n" "http://$LE_HOST/shops" || true
# -k: сертификат от LE staging не доверенный браузером/системой (self-CA staging)
curl -sk -o /dev/null -w "  https://$LE_HOST/shops  -> HTTP %{http_code}\n" "https://$LE_HOST/shops" || true
echo "  (issuer сертификата:)"
echo | openssl s_client -connect "$LE_HOST:443" -servername "$LE_HOST" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true
echo
echo "=== ГОТОВО: https://$LE_HOST/shops  (staging = самоподписанный, это ожидаемо) ==="
echo "Снести всё:  cd terraform && terraform destroy -auto-approve"
