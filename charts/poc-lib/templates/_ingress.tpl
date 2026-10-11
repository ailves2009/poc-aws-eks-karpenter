{{- define "poc-lib.ingress" -}}
{{- $ing := .app.ingress -}}
{{- if not .app.service -}}
{{- fail (printf "applications.%s.ingress is enabled but service is not: the Ingress routes to the Service" .name) -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "poc-lib.fullname" . }}
  labels:
    {{- include "poc-lib.labels" . | nindent 4 }}
  {{- with $ing.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ required "ingress.className is required" $ing.className }}
  rules:
    - host: {{ required (printf "applications.%s.ingress.host is required" .name) $ing.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "poc-lib.fullname" . }}
                port:
                  name: http
{{- end -}}
