#!/usr/bin/env bash
# Configuration gate: submit.sh's refusals plus the review checks the P1 brief asks you to explain. Needs yq v4.
# Run before opening a PR; GitHub Actions runs it on every PR/push.
# Usage: bash scripts/check-config.sh [BASE_REVISION]   (BASE_REVISION enables the config-revision bump check)
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/p1.env
f=configuration/app/resources.yaml
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
q() { yq "$1" "${2:-$f}"; }
deploy='.items[] | select(.kind=="Deployment")'
cm='.items[] | select(.kind=="ConfigMap")'

if grep -q REPLACE_WITH_ "$f"; then fail "REPLACE_WITH_ placeholders remain in $f"; else pass "no REPLACE_WITH_ placeholders"; fi

v="$(q "$deploy | .spec.template.spec.containers[0].image")"
[ "$v" = "$P1_IMAGE" ] && pass "image = $v" || fail "image = '$v' (expected the imported label $P1_IMAGE)"
v="$(q "$cm | .data.LAB_SESSION")"
[ "$v" = "$P1_SESSION" ] && pass "LAB_SESSION = $v" || fail "LAB_SESSION = '$v' (expected $P1_SESSION)"
v="$(q "$cm | .data.LOCAL_LOKI_URL")"
[ "$v" = "$P1_CLUSTER_LOKI_URL" ] && pass "LOCAL_LOKI_URL = $v" || fail "LOCAL_LOKI_URL = '$v' (expected $P1_CLUSTER_LOKI_URL)"

cluster_env="$(q "$cm | .data.LAB_ENV")"
case "$cluster_env" in workshop-blue|workshop-green) pass "LAB_ENV = $cluster_env";; *) fail "LAB_ENV = '$cluster_env' (workshop-blue or workshop-green)";; esac
local_env="$(sed -n 's/^LAB_ENV=//p' runtime.env)"
[ "$local_env" = "$cluster_env" ] && pass "runtime.env LAB_ENV matches the ConfigMap" \
  || fail "runtime.env LAB_ENV '$local_env' differs from ConfigMap '$cluster_env' (keep one intended environment)"

v="$(q "$deploy | .spec.replicas")"
[ "$v" = 1 ] && pass "replicas = 1" || fail "replicas = '$v' (keep one replica)"
v="$(q "$deploy | .spec.template.spec.containers[0].imagePullPolicy")"
[ "$v" = Never ] && pass "imagePullPolicy = Never (local image import)" || fail "imagePullPolicy = '$v' (expected Never)"

# ponytail: compares only the `app` label, which is the only selector key this manifest uses.
svc="$(q '.items[] | select(.kind=="Service") | .spec.selector.app')"
pod="$(q "$deploy | .spec.template.metadata.labels.app")"
[ "$svc" = "$pod" ] && pass "Service selector app=$svc matches the Pod template label" \
  || fail "Service selector app=$svc does not match Pod template label app=$pod (the Service will have no endpoints)"

d="$(yq -p json -oy '.deadlineMs' app/wwwroot/client.json)"
r="$(yq -p json -oy '.retries' app/wwwroot/client.json)"
case "$d$r" in *[!0-9]*|'') fail "client.json deadlineMs/retries must be integers";;
  *) if [ "$d" -ge 40 ] && [ "$d" -le 650 ] && [ "$r" -le 2 ] && [ $((d * (r + 1))) -le 650 ]; then
       pass "client.json deadlineMs=$d retries=$r (budget $((d * (r + 1))) <= 650)"
     else fail "client.json deadlineMs=$d retries=$r outside 40-650 / 0-2 / budget 650"; fi;; esac

base="${1:-}"
if [ -n "$base" ] && git show "$base:$f" > /tmp/p1-base.yaml 2>/dev/null && ! grep -q REPLACE_WITH_ /tmp/p1-base.yaml; then
  old_cm="$(yq -o=json -I=0 "$cm | .data" /tmp/p1-base.yaml)"; new_cm="$(yq -o=json -I=0 "$cm | .data" "$f")"
  ann="$deploy | .spec.template.metadata.annotations[\"academy/config-revision\"]"
  old_rev="$(q "$ann" /tmp/p1-base.yaml)"; new_rev="$(q "$ann")"
  if [ "$old_cm" != "$new_cm" ] && [ "$old_rev" = "$new_rev" ]; then
    fail "ConfigMap changed but academy/config-revision is still $new_rev (no fresh Pod would start)"
  else pass "academy/config-revision consistent with ConfigMap changes ($old_rev -> $new_rev)"; fi
fi

if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fails check(s))"; exit 1; fi
