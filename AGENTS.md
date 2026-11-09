# Agent context: P1 foundation deployment (GitHub + minikube + Argo CD)

Read this before changing anything. It is the shared brief for Codex, Claude Code and any other coding agent.

## What this repository is
Project 1 of the BP Software Engineering Academy, Week 1 ("Deploy the game foundation"), moved from the classroom
Kubernetes/Argo CD environment to a personal MacBook Air M2 (Apple silicon, arm64) with Docker Desktop and minikube.
The facilitator approved this route and it replaces the classroom deliverable. The repository is public on GitHub
(`islandawolfe-02`).

Outcome: a reproducible deployment of the supplied foundation page and board API, with one bounded configuration
failure (diagnosed and recovered) and a handover README that a peer can follow.

Mapping from the classroom to this repository:

| Classroom | Here |
|---|---|
| `podman build` / `podman run` | `docker build` / `docker run -p 127.0.0.1:18080:8080` (Docker Desktop has no `--network host` to the Mac) |
| host `dotnet publish` and then `COPY publish/` | multi-stage `Containerfile`: the same publish runs inside pinned `sdk:10.0.401` |
| facilitator imports the image into the nodes | `minikube image load "$P1_IMAGE"` (keeps the image ID; `imagePullPolicy: Never`) |
| environment-session variables | `scripts/p1.env` (public values only) |
| `configuration/` local repo + `submit.sh` | `configuration/app/` in this repo; a merged, self-reviewed pull request on `main` |
| facilitator or peer review | self-review on the PR (decision recorded as a PR comment) |
| prepared Argo CD Application `p1-...` | `argocd/application.yaml`, applied by `scripts/setup-cluster.sh` (Argo CD v3.5.2 core) |
| prepared Loki/Grafana | `observability/` (same images, datasource and dashboard as W1.10) |
| W1.07 packaging gate | `.github/workflows/p1-gates.yml` + `scripts/smoke.sh` + `scripts/check-config.sh` |

## Hard rules
- **Do not edit `app/`** except `app/wwwroot/client.json`. It is supplied teaching code (release `foundation-observe-a`).
  No C#/TypeScript programming is part of this project.
- In `configuration/app/resources.yaml`, keep the resource names (`foundation`, `foundation-settings`), `replicas: 1`,
  `DOTNET_PROCESSOR_COUNT`, `imagePullPolicy: Never` and the `/healthz` probes.
- When the ConfigMap changes, increment `academy/config-revision` in the Pod template **in the same commit**.
- `client.json`: `deadlineMs` 40–650, `retries` 0–2, `deadlineMs × (retries + 1) ≤ 650`.
- Keep `runtime.env` `LAB_ENV` and the ConfigMap `LAB_ENV` the same (`workshop-blue` or `workshop-green`).
- Never commit kubeconfig, tokens or credentials. `instructions.md` is the owner's private runbook and is git-ignored.
- **Never invent evidence.** Image IDs, commits, request IDs, timestamps and Grafana rows must come from real command
  output. Leave `____` blanks rather than guessing. Do not relabel raw stdout as a Grafana observation.
- Label status honestly: *executed on personal minikube (date)* / *historical (lab, date)* / *pending* /
  *unavailable on BP*. This is **not** a BP Yalla scaffold, BP pull request or BP deployment. Those stay pending
  because the approved walkthrough was not supplied.
- The CI image is an amd64 rebuild used only for the gate. The deployed image is the one built on the Mac and loaded
  into minikube. Never conflate the two image IDs.
- Course integrity: the learner writes first attempts, predictions and individual explanations. Agents may explain,
  check and fix tooling, but should not write the learner's predictions or reflections as if they were the learner's.

## Layout
```
app/                       supplied foundation (ASP.NET Core net10.0): page + /api/boards/{id} + /healthz on 8080
Containerfile              owned packaging recipe (multi-stage, digest-pinned)
runtime.env                owned: LAB_ENV for the local docker run
configuration/app/resources.yaml   owned desired state: ConfigMap + Deployment + Service (Argo CD path)
argocd/application.yaml    Argo CD Application template (tokens filled by setup-cluster.sh)
observability/             Loki 3.7.8 + Grafana 13.2.3 for minikube (kustomize)
scripts/p1.env             session variables (P1_NAMESPACE, P1_SESSION, P1_IMAGE, Loki/Grafana URLs)
scripts/smoke.sh           receipt checks: health, page, reference body/headers, request-id echo, missing 404
scripts/check-config.sh    config gate: placeholders, image label, session, Loki URL, env, selector, budget, annotation
scripts/setup-cluster.sh   one-time minikube + Argo CD + Loki/Grafana + namespace + Application
.github/workflows/p1-gates.yml  CI: package gate (build + smoke) and configuration gate; never deploys
evidence/                  real outputs per milestone (committed)
evidence-log.md            milestone log;  README.md = handover README
```

## Commands (zsh on macOS, from the repository root)
```bash
source scripts/p1.env
docker build -f Containerfile -t "$P1_IMAGE" .
docker run -d --name "$P1_NAMESPACE-local" -p 127.0.0.1:18080:8080 --env-file runtime.env \
  -e LAB_SESSION="$P1_SESSION" -e LOCAL_LOKI_URL="$P1_LOCAL_LOKI_URL" "$P1_IMAGE"
bash scripts/smoke.sh http://127.0.0.1:18080 workshop-blue evidence/m2-local
bash scripts/check-config.sh                 # needs yq v4 (brew install yq)
minikube image load "$P1_IMAGE"
argocd --core app sync "$P1_NAMESPACE" --revision "$P1_REVISION"
kubectl -n "$P1_NAMESPACE" port-forward service/foundation 18081:8080
```
Grafana query: `{job="academy-w110", session="<P1_SESSION>"} | json | request_id="<actual id>"`.
The job name stays `academy-w110` because the supplied runtime keeps it. Session and request ID identify this run.

## Milestones (update the status as work happens)
| # | Milestone | Status |
|---|---|---|
| 1 | Plan and baseline (evidence-log.md section 1) | pending |
| 2 | Package and run locally (docker, smoke, Grafana) | pending |
| 3 | Review proposal (PR filling resources.yaml placeholders) | pending |
| 4 | Deploy through Argo CD on minikube, verify via port-forward 18081 | pending |
| 5 | Selector failure (`app: foundation-missing`) and recovery; then blue → green with annotation bump | pending |
| 6 | Handover README; reproduce from a fresh clone | pending |
| 7 | Individual demonstration | pending |
