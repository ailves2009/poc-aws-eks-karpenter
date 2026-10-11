{{- define "poc-lib.hpa" -}}
{{- $hpa := .app.autoscaling -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "poc-lib.fullname" . }}
  labels:
    {{- include "poc-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "poc-lib.fullname" . }}
  minReplicas: {{ $hpa.minReplicas | default 1 }}
  maxReplicas: {{ required "autoscaling.maxReplicas is required" $hpa.maxReplicas }}
  metrics:
    # Average CPU as a fraction of requests.cpu -- requests must be set.
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $hpa.targetCPU | default 70 }}
{{- end -}}
