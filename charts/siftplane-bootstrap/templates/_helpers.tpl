{{- define "bootstrap.name" -}}
siftplane-bootstrap-{{ .Values.installation.namespace | sha256sum | trunc 32 }}
{{- end -}}
{{- define "bootstrap.labels" -}}
app.kubernetes.io/name: siftplane-bootstrap
app.kubernetes.io/instance: {{ include "bootstrap.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}
{{- define "bootstrap.keep" -}}
helm.sh/resource-policy: keep
{{- end -}}
{{- define "bootstrap.context" -}}
{{ dict "schema_version" 1 "bootstrap_namespace" .Release.Namespace "target_namespace" .Values.installation.namespace "kubernetes_url" .Values.installation.kubernetes.url "lifetime_seconds" .Values.installation.lifetime_seconds "options_sha256" (toJson .Values.installation | sha256sum) | toJson }}
{{- end -}}
{{- define "bootstrap.validate" -}}
{{- if .Release.IsUpgrade -}}{{ fail "This chart starts an installation once. Recover the retained bootstrap Job; use the deployment agent for service upgrades." }}{{- end -}}
{{- $target := .Values.installation.namespace -}}
{{- range (list .Release.Namespace $target) -}}
{{- if or (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .)) (gt (len .) 63) (eq . "default") (hasPrefix "kube-" .) -}}{{ fail "Use dedicated bootstrap and target namespaces." }}{{- end -}}
{{- end -}}
{{- if eq .Release.Namespace $target -}}{{ fail "Bootstrap and target namespaces must be distinct." }}{{- end -}}
{{- if gt (len (toJson .Values)) 32768 -}}{{ fail "Bootstrap values exceed 32768 bytes." }}{{- end -}}
{{- range (list .Values.installation.kubernetes .Values.installation.telemetry) -}}
{{- include "bootstrap.endpoint" . -}}
{{- end -}}
{{- range concat .Values.installation.dns_cidrs .Values.installation.ingress_cidrs -}}
{{- include "bootstrap.cidr" . -}}
{{- end -}}
{{- range concat .Values.runner.registry (list .Values.installation.kubernetes.network .Values.installation.telemetry.network) -}}
{{- range .cidrs -}}{{- include "bootstrap.cidr" . -}}{{- end -}}
{{- end -}}
{{- if eq .Values.installation.foundation.mode "create" -}}
{{- range .Values.installation.foundation.api_server_cidrs -}}{{- include "bootstrap.cidr" . -}}{{- end -}}
{{- $foundation := .Values.installation.foundation.namespace -}}
{{- if or (eq $foundation $target) (eq $foundation .Release.Namespace) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $foundation)) (gt (len $foundation) 63) (eq $foundation "default") (hasPrefix "kube-" $foundation) -}}{{ fail "The shared foundation needs a separate dedicated namespace." }}{{- end -}}
{{- end -}}
{{- $name := include "bootstrap.name" . -}}
{{- $cluster := lookup "v1" "Namespace" "" "kube-system" -}}
{{- $key := printf "deployment.siftplane.com/bootstrap-%s" ($target | sha256sum | trunc 32) -}}
{{- if and $cluster (hasKey ($cluster.metadata.annotations | default dict) $key) -}}{{ fail "A retained bootstrap operation exists for this target. Recover it; do not reinstall the bootstrap chart." }}{{- end -}}
{{- range (list (list "rbac.authorization.k8s.io/v1" "ClusterRole" "" $name) (list "rbac.authorization.k8s.io/v1" "ClusterRoleBinding" "" $name) (list "v1" "ServiceAccount" $.Release.Namespace $name) (list "v1" "ConfigMap" $.Release.Namespace (printf "%s-input" $name))) -}}
{{- if lookup (index . 0) (index . 1) (index . 2) (index . 3) -}}{{ fail "Bootstrap resources already exist. Recover the original Job instead of adopting or recreating its grant." }}{{- end -}}
{{- end -}}
{{- end -}}
