{{- with secret "secret/data/orders/db" -}}
{{ .Data.data.POSTGRES_PASSWORD }}
{{- end -}}
