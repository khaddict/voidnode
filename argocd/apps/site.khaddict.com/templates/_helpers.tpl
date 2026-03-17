{{- define "site-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "site-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "site-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "site-khaddict.labels" -}}
{{ include "site-khaddict.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
