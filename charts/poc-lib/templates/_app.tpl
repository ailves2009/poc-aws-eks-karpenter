{{/*
poc-lib.app — the only entry point. An umbrella chart's templates/resources.yaml is one line:
  {{ include "poc-lib.app" . }}

One render = one service. `activeApp` is mandatory: the ApplicationSet passes it as a Helm
parameter, and rendering several services at once would put their resources into one Argo CD
Application. The service's shape (values/<service>.yaml of the umbrella) arrives as an ordinary
values file through `valueFiles` -- the library reads no files itself, so the umbrella's
values.schema.json sees every value that shapes the render.
*/}}
{{- define "poc-lib.app" -}}
{{- $name := required "activeApp must be set: the ApplicationSet passes it as a Helm parameter (helm template ... --set activeApp=<service>)" .Values.activeApp -}}
{{- $apps := .Values.applications | default dict -}}
{{- if not (hasKey $apps $name) -}}
{{- fail (printf "applications.%s is not defined: pass values/%s.yaml of the chart and the environment file of the service" $name $name) -}}
{{- end -}}
{{- /* common first, the service on top. mergeOverwrite on a deep copy: no toYaml/fromYaml round
       trip, so integers stay integers. Lists are replaced, not merged. */ -}}
{{- $app := mergeOverwrite (deepCopy (.Values.common | default dict)) (deepCopy (index $apps $name)) -}}
{{- $ctx := dict "root" . "name" $name "app" $app -}}
{{- if ($app.serviceAccount | default dict).create }}
---
{{ include "poc-lib.serviceaccount" $ctx }}
{{- end }}
---
{{ include "poc-lib.deployment" $ctx }}
{{- if $app.service }}
---
{{ include "poc-lib.service" $ctx }}
{{- end }}
{{- if ($app.ingress | default dict).enabled }}
---
{{ include "poc-lib.ingress" $ctx }}
{{- end }}
{{- if ($app.autoscaling | default dict).enabled }}
---
{{ include "poc-lib.hpa" $ctx }}
{{- end }}
{{- end -}}
