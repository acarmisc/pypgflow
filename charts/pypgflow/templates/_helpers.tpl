{{/*
Expand the name of the chart.
*/}}
{{- define "pypgflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pypgflow.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pypgflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pypgflow.labels" -}}
helm.sh/chart: {{ include "pypgflow.chart" . }}
{{ include "pypgflow.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pypgflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pypgflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pypgflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pypgflow.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Construct the database URI
*/}}
{{- define "pypgflow.databaseUri" -}}
{{- if .Values.postgresql.enabled }}
postgres://{{ .Values.postgresql.user }}:{{ .Values.postgresql.password }}@{{ include "pypgflow.fullname" . }}-postgresql:{{ .Values.postgresql.port }}/{{ .Values.postgresql.database }}
{{- else }}
postgres://{{ .Values.postgresql.external.user }}:{{ .Values.postgresql.external.password }}@{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- end }}
{{- end }}
