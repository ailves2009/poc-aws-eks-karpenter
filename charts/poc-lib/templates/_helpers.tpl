{{/* Resource name: fullnameOverride or the service name (not prefixed by the release). */}}
{{- define "poc-lib.fullname" -}}
{{- .app.fullnameOverride | default .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels: immutable on a Deployment, so only name + instance. */}}
{{- define "poc-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{- define "poc-lib.labels" -}}
{{ include "poc-lib.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- with .app.image.tag }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with (.root.Values.global | default dict).partOf }}
app.kubernetes.io/part-of: {{ . }}
{{- end }}
{{- end -}}

{{/* repository:tag@digest. The digest is what the kubelet pulls; the tag is for humans. */}}
{{- define "poc-lib.image" -}}
{{- $i := required (printf "applications.%s.image is required" .name) .app.image -}}
{{- printf "%s:%s@%s" (required "image.repository is required" $i.repository) (required "image.tag is required" $i.tag) (required "image.digest is required: images are pinned by digest" $i.digest) -}}
{{- end -}}
