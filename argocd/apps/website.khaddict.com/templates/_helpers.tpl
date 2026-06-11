{{- define "website-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "website-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "website-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "website-khaddict.labels" -}}
{{ include "website-khaddict.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
