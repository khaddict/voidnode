{{- define "changedetection.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "changedetection.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "changedetection.selectorLabels" -}}
app.kubernetes.io/name: {{ include "changedetection.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "changedetection.labels" -}}
{{ include "changedetection.selectorLabels" . }}
helm.sh/chart: {{ include "changedetection.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
