{{- define "dnsutils.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "dnsutils.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dnsutils.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "dnsutils.labels" -}}
{{ include "dnsutils.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
