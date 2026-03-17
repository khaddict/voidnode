{{- define "homepage.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "homepage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homepage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "homepage.labels" -}}
{{ include "homepage.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
