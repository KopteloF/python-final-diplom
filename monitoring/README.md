# Мониторинг (Prometheus + Grafana + Alertmanager)

Стек разворачивается в namespace `monitoring`. Всё декларативно, дашборды — как код.

## Порядок применения

```bash
kubectl apply -f monitoring/

# Дашборды Grafana собираются в ConfigMap из JSON-файлов (dashboards as code).
# ConfigMap не держим статичным манифестом, чтобы JSON оставались валидными файлами
# (удобно редактировать и смотреть diff), а не строками внутри YAML.
kubectl -n monitoring create configmap grafana-dashboards \
  --from-file=monitoring/dashboards/ \
  --dry-run=client -o yaml | kubectl apply -f -

# Подхватить свежие дашборды/провайдер:
kubectl -n monitoring rollout restart deploy/grafana
```

## Дашборды (`dashboards/`)

- `orders-app.json` — приложение: частота запросов по view, ответы по статусам, p95-латентность, суммарный RPS.
- `nodes.json` — ноды: CPU, память, корневой диск, сеть (по нодам).

Все панели ссылаются на datasource по фиксированному `uid: prometheus` (задан в
`grafana-datasources`), поэтому провижнинг детерминированный. Дашборды переживают
пересоздание тома Grafana (в отличие от импортированных через UI).

## Доступ

```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000     # http://localhost:3000 (admin/admin при первом старте)
kubectl -n monitoring port-forward svc/prometheus 9090:9090  # http://localhost:9090/targets
```
