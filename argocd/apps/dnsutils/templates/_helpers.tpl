{{- define "dnsutils.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "dnsutils.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "dnsutils.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dnsutils.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "dnsutils.labels" -}}
{{ include "dnsutils.selectorLabels" . }}
helm.sh/chart: {{ include "dnsutils.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
