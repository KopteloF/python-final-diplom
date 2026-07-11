{{- with secret "secret/data/orders/app" }}
export SECRET_KEY="{{ .Data.data.SECRET_KEY }}"
{{- end }}
{{- with secret "secret/data/orders/db" }}
export DB_PASSWORD="{{ .Data.data.POSTGRES_PASSWORD }}"
{{- end }}
