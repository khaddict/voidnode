{{- define "uptime-kuma.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "uptime-kuma.selectorLabels" -}}
app.kubernetes.io/name: {{ include "uptime-kuma.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "uptime-kuma.labels" -}}
{{ include "uptime-kuma.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
