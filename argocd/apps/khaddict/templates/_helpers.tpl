{{- define "khaddict.name" -}}
{{- printf "%s-khaddict" .site.name -}}
{{- end -}}

{{- define "khaddict.chart" -}}
{{- printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "khaddict.selectorLabels" -}}
app.kubernetes.io/name: {{ include "khaddict.name" . }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{- define "khaddict.labels" -}}
{{ include "khaddict.selectorLabels" . }}
helm.sh/chart: {{ include "khaddict.chart" . }}
{{- if .root.Chart.AppVersion }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}
