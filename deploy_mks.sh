#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Фаза 6 «одной кнопкой»: Managed Service for Kubernetes.
# Terraform поднимает управляемый кластер + node group -> yc даёт kubeconfig ->
# helm ставит приложение (values-cloud, Vault off) -> Service type=LoadBalancer
# отдаёт внешний IP (YC создаёт NLB) -> curl проверяет 200.
#
# Ключевое отличие от self-hosted (deploy_cloud_k8s.sh): здесь НЕТ SSH/Ansible и
# установки k3s — control-plane управляет YC, а мы работаем kubectl'ом с ноутбука.
#
# Требуется: yc CLI (headless на SA-ключ), kubectl, helm, terraform.
# Запуск: cd ~/orders-devops && chmod +x deploy_mks.sh && ./deploy_mks.sh
# Снести всё: cd terraform-mks && terraform destroy -auto-approve
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"; ROOT="$(pwd)"

NS=orders
CLUSTER=orders-mks

echo "== 0/6 Проверки окружения =="
for bin in terraform yc kubectl helm openssl; do
  command -v "$bin" >/dev/null || { echo "НЕ найден '$bin' в PATH"; exit 1; }
done

echo "== 1/6 Terraform apply (управляемый кластер + node group) =="
cd "$ROOT/terraform-mks"
# tfvars (cloud_id/folder_id) переиспользуем из основного конфига — они gitignored.
[ -f terraform.tfvars ] || cp "$ROOT/terraform/terraform.tfvars" terraform.tfvars
terraform init -input=false >/dev/null
terraform apply -auto-approve
CLUSTER="$(terraform output -raw cluster_name)"
echo "   Кластер: $CLUSTER"

echo "== 2/6 kubeconfig через yc (внешний endpoint) =="
cd "$ROOT"
yc managed-kubernetes cluster get-credentials --external --name "$CLUSTER" --force
echo "-- ноды кластера:"
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl get nodes -o wide

echo "== 3/6 Namespace + статичные секреты (Vault на MKS не тащим) =="
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
DB_PASSWORD="$(openssl rand -hex 16)"
SECRET_KEY="$(openssl rand -hex 32)"
kubectl -n "$NS" create secret generic db-credentials \
  --from-literal=POSTGRES_DB=orders_db \
  --from-literal=POSTGRES_USER=orders_user \
  --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic app-secrets \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== 4/6 Helm deploy (values-cloud, Ingress off — на MKS нет Traefik) =="
helm upgrade --install orders "$ROOT/helm/orders" \
  -n "$NS" \
  -f "$ROOT/helm/orders/values-cloud.yaml" \
  --set ingress.enabled=false \
  --wait --timeout 8m
kubectl -n "$NS" rollout status deploy/app --timeout=180s

echo "== 5/6 Публикуем приложение через LoadBalancer (YC NLB) =="
kubectl -n "$NS" expose deployment app --name=app-lb \
  --type=LoadBalancer --port=80 --target-port=8000 \
  --dry-run=client -o yaml | kubectl apply -f -
echo "-- ждём внешний IP от YC..."
LB_IP=""
for i in $(seq 1 40); do
  LB_IP="$(kubectl -n "$NS" get svc app-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "$LB_IP" ] && break
  echo "   ...ждём ($i)"; sleep 6
done
[ -n "$LB_IP" ] || { echo "LB IP не выдан за отведённое время — проверь Service app-lb"; exit 1; }
echo "   LB IP: $LB_IP"

echo "== 6/6 Проверка приложения =="
for i in $(seq 1 20); do
  CODE="$(curl -m 5 -s -o /dev/null -w '%{http_code}' "http://$LB_IP/shops" || echo 000)"
  echo "   http://$LB_IP/shops -> $CODE"
  [ "$CODE" = "200" ] && break
  sleep 6
done

echo
echo "=== ГОТОВО: приложение работает в Managed Kubernetes. ==="
echo "URL:      http://$LB_IP/shops"
echo "Кластер:  $CLUSTER"
echo "Снести:   cd terraform-mks && terraform destroy -auto-approve"
