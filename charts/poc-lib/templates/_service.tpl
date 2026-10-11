{{- define "poc-lib.service" -}}
{{- $svc := .app.service -}}
{{- if not .app.containerPort -}}
{{- fail (printf "applications.%s.service is set but containerPort is not: the Service targets the named port \"http\"" .name) -}}
{{- end -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "poc-lib.fullname" . }}
  labels:
    {{- include "poc-lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "poc-lib.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ $svc.port }}
      targetPort: http
      protocol: TCP
{{- end -}}
