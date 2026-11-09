#!/usr/bin/env bash
# One-time environment preparation on the Mac (the classroom facilitator's job): minikube, Argo CD (core mode,
# as `argocd --core` in class), Loki/Grafana, your p1-... namespace and Argo CD Application. Safe to re-run.
# Usage (from the repository root, after `git remote add origin ...`): bash scripts/setup-cluster.sh [REPO_HTTPS_URL]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/p1.env
ARGOCD_VERSION=v3.5.2   # course pin
for t in docker minikube kubectl argocd yq git; do
  command -v "$t" >/dev/null || { echo "MISSING: $t (brew install $t)" >&2; exit 1; }
done

repo_url="${1:-$(git remote get-url origin)}"
case "$repo_url" in git@github.com:*) repo_url="https://github.com/${repo_url#git@github.com:}";; esac
echo "Argo CD will read: $repo_url (path configuration/app, branch main)"

# Docker runtime inside minikube, so `minikube ssh -- docker image inspect` shows the imported image ID.
minikube status >/dev/null 2>&1 || minikube start --driver=docker --container-runtime=docker
kubectl config use-context minikube
echo "minikube container runtime: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/core-install.yaml"
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

kubectl apply -k observability
kubectl -n observability rollout status deployment/loki --timeout=300s
kubectl -n observability rollout status deployment/grafana --timeout=300s

kubectl create namespace "$P1_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|__P1_NAMESPACE__|$P1_NAMESPACE|" -e "s|__REPO_URL__|$repo_url|" argocd/application.yaml | kubectl apply -f -

# argocd --core reads Applications from the current kubectl namespace.
kubectl config set-context --current --namespace=argocd
argocd --core app get "$P1_NAMESPACE" || true
echo "READY: Argo CD $ARGOCD_VERSION (core), Loki, Grafana, namespace $P1_NAMESPACE, Application $P1_NAMESPACE"
