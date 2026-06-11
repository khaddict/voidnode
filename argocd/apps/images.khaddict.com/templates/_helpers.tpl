{{- define "images-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "images-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "images-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "images-khaddict.labels" -}}
{{ include "images-khaddict.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
