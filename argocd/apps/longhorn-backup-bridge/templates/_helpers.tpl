{{- define "longhorn-backup-bridge.name" -}}
{{- default .Chart.Name .Values.app -}}
{{- end -}}

{{- define "longhorn-backup-bridge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "longhorn-backup-bridge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "longhorn-backup-bridge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "longhorn-backup-bridge.labels" -}}
{{ include "longhorn-backup-bridge.selectorLabels" . }}
helm.sh/chart: {{ include "longhorn-backup-bridge.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
