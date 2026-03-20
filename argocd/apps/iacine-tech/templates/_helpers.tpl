{{- define "iacine-tech.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "iacine-tech.selectorLabels" -}}
app.kubernetes.io/name: {{ include "iacine-tech.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "iacine-tech.labels" -}}
{{ include "iacine-tech.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
