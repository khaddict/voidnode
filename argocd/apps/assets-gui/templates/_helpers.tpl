{{- define "assets-gui.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "assets-gui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "assets-gui.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "assets-gui.labels" -}}
{{ include "assets-gui.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
