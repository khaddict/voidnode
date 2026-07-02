{{- define "www-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "www-khaddict.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "www-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "www-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "www-khaddict.labels" -}}
{{ include "www-khaddict.selectorLabels" . }}
helm.sh/chart: {{ include "www-khaddict.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
