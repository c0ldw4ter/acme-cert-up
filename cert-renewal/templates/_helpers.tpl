{{/* Общие вспомогательные функции */}}
{{- define "cert-renewal.name" -}}
{{- default .Chart.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cert-renewal.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "cert-renewal.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}