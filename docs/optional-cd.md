# Optional image publishing and CD

This is an additional route for the supplied foundation. The existing `p1-gates`
workflow, local Docker build, `minikube image load`, manual Argo sync and
`configuration/app/resources.yaml` keep their existing behaviour.

The optional workflow is `.github/workflows/publish-deploy.yml`. It runs only
when selected in GitHub Actions; it does not run on ordinary pushes or pull
requests. Its registry image is separate from both the original Mac image and
the temporary image built by `p1-gates`.

## Current status

The app-side publishing workflow passed on GitHub on 2026-11-16:
[run #2](https://github.com/islandawolfe-02/Basic-GitOps-using-Argo-CD-and-Minikube/actions/runs/43907745486),
source commit `d976bded19d03788f3523ebde942375902856b4e`. Pre-publication
checks, ARM64/AMD64 publication and both registry smoke checks passed; the
deployment request was skipped.

The receiving `deploy.yml` workflow and Argo bootstrap in
`islandawolfe-02/ARGO-CD-GitOPS-Deployments` are step 6 and must exist before
selecting **Deploy**. Deployment through this route remains pending.

## Run the workflow

Merge the workflow and its supporting scripts into the app repository's default
branch. Open **Actions → Optional image publish and deployment → Run workflow**.
The selected branch supplies the application source and `runtime.env` settings.

| Build image | Deploy | Behaviour |
|---|---|---|
| Yes | No | Smoke-test locally on the runner, publish ARM64/AMD64 to GHCR, then smoke-test both published architectures |
| Yes | Yes | Perform the publishing checks, then send the exact image digest to the deployment repository |
| No | Yes | Pull and smoke-test an existing package digest on both architectures, then request deployment |
| No | No | Skip the job |

For the first run, select **Build image: Yes** and **Deploy: No**. No dispatch
secret or namespace is needed for this publishing-only run.

The package name is `ghcr.io/<lowercase-app-repository-owner>/<lowercase-app-repository-name>`.
For this app it is
`ghcr.io/islandawolfe-02/basic-gitops-using-argo-cd-and-minikube`.
The workflow links the package to this repository and labels its source commit.
It uses a unique source-commit/run/attempt tag and records the immutable digest
in its summary and the `optional-cd-<run>-<attempt>` artifact.

The registry smoke checks pull each architecture by its own child manifest
digest to avoid Docker's cross-platform digest-reference collision. The saved
deployment request keeps the parent multi-platform digest for minikube to select
its matching architecture.

After the first successful publication, make the package public in its GitHub
package settings so minikube can pull it without credentials. GitHub repository
visibility does not automatically make a new package public.

## Request deployment

Add the repository secret `CD_DISPATCH_TOKEN` in the app repository. Use a
fine-grained token restricted to `ARGO-CD-GitOPS-Deployments` with **Actions:
read and write**; the app's own `GITHUB_TOKEN` handles package publishing.

Select **Deploy: Yes**, enter your namespace and deployment name, and choose
three distinct Mac port-forward ports. Defaults are app `18090`, Grafana `3001`
and Loki `3101`; these values do not start a port-forward on your Mac.

The workflow rejects the original project namespace, `observability`, `argocd`,
`default`, `kube-*`, and the original project/reproduction ports. This checks the
request only: the receiver must enforce resource ownership, and you must check
whether another local process already occupies a selected port.

When **Build image: No**, supply the complete package reference ending in
`@sha256:<digest>`, copied from a previous successful run. It must belong to this
app's package, provide both architectures, carry this repository's source and
commit labels, and pass the current foundation smoke checks; `latest` is not
accepted.

## Receiver contract for step 6

The caller sends a `workflow_dispatch` request to
`islandawolfe-02/ARGO-CD-GitOPS-Deployments`, workflow `deploy.yml`, ref `main`.
The receiver must declare these string inputs and validate them again:

| Input | Meaning |
|---|---|
| `project` | `foundation`, identifying this project's deployment settings |
| `source_repository` | App repository in `owner/repo` form |
| `source_revision` | Source commit read from the verified image's labels |
| `image` | Full GHCR package reference pinned by digest |
| `namespace` | User-selected additional deployment namespace |
| `deployment_name` | User-selected installation name |
| `app_port` | Mac port-forward port for the new app |
| `grafana_port` | Mac port-forward port for the new Grafana |
| `loki_port` | Mac port-forward port for the new Loki |
| `lab_env` | Current `runtime.env` value: `workshop-blue` or `workshop-green` |

The new foundation deployment should listen on `8081`; the optional workflow
already tests that listener override. Step 6 will configure the separate
Grafana/Loki listeners, Services, probes and datasource, and produce matching
local port-forward commands without changing the original observation stack.

A successful dispatch means GitHub accepted the request. Follow the receiving
workflow and verify Argo sync, Pod readiness, endpoints, browser response and
Grafana records before recording a successful deployment. GitHub-hosted runners
do not need access to the Mac's Kubernetes API; the existing Argo installation
will reconcile the new Application from inside minikube.

The manual local-image route remains available. Offline use still requires its
build dependencies, images and Git revision to be available locally; publishing
and uncached registry pulls need network access.

References: [manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow),
[workflow dispatch](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event),
[GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry),
[multi-platform builds](https://docs.docker.com/build/ci/github-actions/multi-platform/).
