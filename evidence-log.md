# Project 1 evidence log

Route: personal minikube on a MacBook Air M2, with GitHub PRs and Argo CD v3.5.2 core (facilitator-approved
replacement for the classroom environment). Operator / predictor: islandawolfe-02 for both (solo, self-reviewed).

## 1. Plan and baseline (write before Milestone 2)
* Game intention (do not implement): action ____ / state ____ / completion condition ____ (reference: treasure hunt)
* Destination: namespace `p1-islandawolfe-02`, Argo CD Application `p1-islandawolfe-02`, minikube context `minikube`
* Reviewer: islandawolfe-02 (self-review on GitHub PRs)
* Historical baseline (W1.10, 2026-11-02, local WSL, emulated client): Reference 200 in 7–9 ms, Missing 404, Slow
  about 302 ms of server time (400/0 received it, 200/2 did not), Overdue 902 ms (unavailable), workshop-blue.
* Fresh smoke expectations: the page loads; Reference gives HTTP 200 and the exact `app/data/board-reference.json` (3×3, 6 moves);
  `/healthz` gives Healthy; the release is `foundation-observe-a`; the environment is my `LAB_ENV`; Missing gives a separate 404 NOT_FOUND.

## Milestone log
| Time (UTC) | Milestone | Observation (command, result, identifiers) | Evidence file |
|---|---|---|---|
| | 2 local image ID / smoke / Grafana row | | evidence/m2-local/ |
| | 3 review decision (PR #, full commit) | | PR link |
| | 4 Argo revision / Pod image ID / endpoint / response / Grafana row | | evidence/m4-deploy/ |
| | 5 failure: prediction, empty endpoints, failed port-forward, healthy Pod | | evidence/m5-failure/ |
| | 5 recovery: corrective revision, fresh request | | evidence/m5-recovery/ |
| | 5 blue → green: annotation bump, header | | evidence/m5-green/ |
| | 6 fresh-clone reproduction: image ID, comparison | | evidence/m6-reproduce/ |

Individual reflection: assistance used ____; one rejected repair and why ____; one next learning step ____.
