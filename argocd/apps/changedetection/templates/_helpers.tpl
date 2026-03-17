{{- define "changedetection.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "changedetection.selectorLabels" -}}
app.kubernetes.io/name: {{ include "changedetection.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "changedetection.labels" -}}
{{ include "changedetection.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
