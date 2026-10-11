{{/*
Selector labels. Kept identical to the previous bitnami/nginx release
(app.kubernetes.io/name + instance) because Deployment selectors are
immutable — this lets `helm upgrade` switch charts in place.
*/}}
{{- define "nginx-demo.selectorLabels" -}}
app.kubernetes.io/name: nginx
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "nginx-demo.labels" -}}
{{ include "nginx-demo.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "nginx-demo.image" -}}
{{ .repository }}:{{ .tag }}{{ with .digest }}@{{ . }}{{ end }}
{{- end }}
