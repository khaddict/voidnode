{{- define "images-khaddict.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "images-khaddict.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "images-khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "images-khaddict.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "images-khaddict.labels" -}}
{{ include "images-khaddict.selectorLabels" . }}
helm.sh/chart: {{ include "images-khaddict.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
