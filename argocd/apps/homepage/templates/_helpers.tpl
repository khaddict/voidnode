{{- define "homepage.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "homepage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "homepage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homepage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "homepage.labels" -}}
{{ include "homepage.selectorLabels" . }}
helm.sh/chart: {{ include "homepage.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
