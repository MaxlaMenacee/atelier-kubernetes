#!/usr/bin/env bash
# Vérifie l'avancement de l'atelier. Usage : ./scripts/check.sh
# Ce script ne modifie rien : il se contente de lire l'état du cluster.

cd "$(dirname "$0")/.." || exit 1
PASS=0; TOTAL=0
GREEN="\033[32m"; RED="\033[31m"; GREY="\033[90m"; BOLD="\033[1m"; RESET="\033[0m"

check() { # check "description" commande...
  local desc="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${RESET} $desc"; PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✘${RESET} $desc"
  fi
}
section() { echo -e "\n${BOLD}$1${RESET}"; }
jp() { kubectl get "$@" 2>/dev/null; } # raccourci lecture

# --- Fonctions de test -------------------------------------------------------
cluster_exists()     { k3d cluster list lab; }
three_nodes_ready()  { [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -cw Ready)" -eq 3 ]; }
lb_port_mapped()     { docker ps --format '{{.Ports}}' | grep -q '8081->80'; }
deploy_available()   { [ "$(jp deploy "$1" -n "${2:-default}" -o jsonpath='{.status.availableReplicas}')" -ge 1 ]; }
svc_exists()         { jp svc "$1" -n "${2:-default}"; }
site_uses_cm()       { jp deploy site -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}' | grep -qw site-html; }
site_image_pinned()  { jp deploy site -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -Eq '^nginx:[0-9]'; }
site_endpoints()     { [ -n "$(jp endpoints site -o jsonpath='{.subsets[*].addresses[*].ip}')" ]; }
site_3_replicas()    { [ "$(jp deploy site -o jsonpath='{.status.readyReplicas}')" -ge 3 ]; }
site_on_2_nodes()    { [ "$(kubectl get pods -l app=site -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | grep -c .)" -ge 2 ]; }
site_rolled_out()    { [ "$(kubectl rollout history deploy/site 2>/dev/null | grep -cE '^[0-9]+')" -ge 2 ]; }
manifests_done()     { ! grep -q 'TODO' k8s/site/deployment.yaml k8s/site/service.yaml; }
ingress_ok()         { jp ingress site && curl -sf http://localhost:8081 | grep -qi '<h1>'; }
site_probes()        { jp deploy site -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' | grep -q .; }
site_limits()        { jp deploy site -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' | grep -q .; }

# --- Vérifications ------------------------------------------------------------
section "Exercice 1 — Cluster"
check "Le cluster k3d 'lab' existe"                       cluster_exists
check "3 nœuds sont Ready (1 server + 2 agents)"          three_nodes_ready
check "Le port 8081 est relié au load balancer"           lb_port_mapped

section "Exercice 2 — Premier déploiement"
check "Le Deployment 'web' est disponible"                deploy_available web
check "Le Service 'web' existe"                           svc_exists web

section "Exercice 4 — Déclaratif"
check "Les TODO des manifestes k8s/site/ sont complétés"  manifests_done
check "Le Deployment 'site' est disponible"               deploy_available site
check "'site' utilise la ConfigMap 'site-html'"           site_uses_cm
check "Le Service 'site' a des endpoints"                 site_endpoints

section "Exercice 5 — Scaling & mises à jour"
check "'site' a au moins 3 réplicas prêts"                site_3_replicas
check "Les pods 'site' sont répartis sur ≥ 2 nœuds"       site_on_2_nodes
check "L'image de 'site' est versionnée (nginx:x.y)"      site_image_pinned
check "Au moins une mise à jour a été déployée"           site_rolled_out

section "Exercice 6 — Portainer & Mario"
check "Portainer est disponible"                          deploy_available portainer portainer
check "Le Deployment 'mario' est disponible"              deploy_available mario

section "Bonus"
check "A — L'Ingress 'site' répond sur le port 8081"      ingress_ok
check "B — 'site' a une readinessProbe"                   site_probes
check "B — 'site' a des limites de ressources"            site_limits

echo -e "\n${BOLD}Score : $PASS / $TOTAL${RESET}  ${GREY}(l'exercice 3 n'est pas vérifiable automatiquement)${RESET}"
