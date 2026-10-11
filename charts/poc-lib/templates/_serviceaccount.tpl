{{- define "poc-lib.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "poc-lib.fullname" . }}
  labels:
    {{- include "poc-lib.labels" . | nindent 4 }}
  {{- /* IRSA: eks.amazonaws.com/role-arn goes here, from the environment file. */}}
  {{- with .app.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .app.automountServiceAccountToken | default false }}
{{- end -}}
