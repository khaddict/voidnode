{{- define "www-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "www-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "www-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "www-khaddict.labels" -}}
{{ include "www-khaddict.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
