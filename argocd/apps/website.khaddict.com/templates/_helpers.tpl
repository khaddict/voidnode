{{- define "website-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "website-khaddict.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "website-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "website-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "website-khaddict.labels" -}}
{{ include "website-khaddict.selectorLabels" . }}
helm.sh/chart: {{ include "website-khaddict.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
