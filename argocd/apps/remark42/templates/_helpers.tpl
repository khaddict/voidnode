{{- define "remark42.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "remark42.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "remark42.selectorLabels" -}}
app.kubernetes.io/name: {{ include "remark42.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "remark42.labels" -}}
{{ include "remark42.selectorLabels" . }}
helm.sh/chart: {{ include "remark42.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
