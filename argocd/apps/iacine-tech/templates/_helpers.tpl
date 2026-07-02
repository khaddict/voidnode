{{- define "iacine-tech.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "iacine-tech.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "iacine-tech.selectorLabels" -}}
app.kubernetes.io/name: {{ include "iacine-tech.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "iacine-tech.labels" -}}
{{ include "iacine-tech.selectorLabels" . }}
helm.sh/chart: {{ include "iacine-tech.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
