{{- define "poc-lib.deployment" -}}
{{- $app := .app -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "poc-lib.fullname" . }}
  labels:
    {{- include "poc-lib.labels" . | nindent 4 }}
spec:
  {{- /* With an HPA the replica count belongs to the HPA; setting it here would fight it on every sync. */}}
  {{- if not ($app.autoscaling | default dict).enabled }}
  replicas: {{ $app.replicas | default 1 }}
  {{- end }}
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      {{- include "poc-lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "poc-lib.labels" . | nindent 8 }}
    spec:
      {{- if ($app.serviceAccount | default dict).create }}
      serviceAccountName: {{ include "poc-lib.fullname" . }}
      {{- end }}
      automountServiceAccountToken: {{ $app.automountServiceAccountToken | default false }}
      {{- with $app.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $app.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $app.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $app.topologySpreadConstraints }}
      {{- /* The labelSelector is always this service's own selector, so values never repeat it. */}}
      {{- $selector := dict "matchLabels" (include "poc-lib.selectorLabels" $ | fromYaml) }}
      {{- $constraints := list }}
      {{- range . }}
      {{- $constraints = append $constraints (merge (dict "labelSelector" $selector) .) }}
      {{- end }}
      topologySpreadConstraints:
        {{- toYaml $constraints | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .name }}
          image: {{ include "poc-lib.image" . }}
          imagePullPolicy: IfNotPresent
          {{- with $app.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.args }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.containerPort }}
          ports:
            - name: http
              containerPort: {{ . }}
              protocol: TCP
          {{- end }}
          {{- with $app.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $app.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with $app.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
