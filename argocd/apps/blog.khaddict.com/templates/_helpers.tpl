{{- define "blog-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "blog-khaddict.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "blog-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "blog-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "blog-khaddict.labels" -}}
{{ include "blog-khaddict.selectorLabels" . }}
helm.sh/chart: {{ include "blog-khaddict.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
