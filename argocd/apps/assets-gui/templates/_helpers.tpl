{{- define "assets-gui.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "assets-gui.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "assets-gui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "assets-gui.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "assets-gui.labels" -}}
{{ include "assets-gui.selectorLabels" . }}
helm.sh/chart: {{ include "assets-gui.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
