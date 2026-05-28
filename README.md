# Serverless Health Check API

POST to `/health` with a JSON payload → Lambda validates the input, stores the request in DynamoDB, returns `{"status": "healthy"}`. Two environments (staging, prod), all infrastructure in Terraform, deployed via GitHub Actions.

---

## Architecture Graph

```text
GitHub Actions
     |
     v
Terraform -----------> AWS
                          |
      API Gateway -> Lambda -> DynamoDB
                          |
                    CloudWatch Logs
                          |
                        X-Ray
```

## Deployment Flow

```text
Pull Request / Push to main
          |
          v
   GitHub Actions
          |
          +--> pip-audit
          +--> Terraform fmt / validate
          +--> Checkov
          +--> Terraform plan
          |
          v
 GitHub Environment Approval
          |
          v
   Terraform Apply
          |
          v
+---------------- AWS ----------------+
| API Gateway -> Lambda -> DynamoDB   |
|                    |                |
|                    v                |
|          CloudWatch Logs + X-Ray    |
+-------------------------------------+
```

## Application Logic

Every request to `/health` goes through the same sequence:

1. **Log to CloudWatch** — the raw event is logged immediately on entry, tagged with the
   Lambda request ID so you can correlate log lines across a single invocation:
   ```
   [abc-123] Received event: {"version":"2.0","routeKey":"POST /health",...}
   ```

2. **Validate input** — the body must be valid JSON and must contain a non-null, non-empty
   `payload` key. Anything else returns 400 before touching DynamoDB:
   ```json
   {"error": "Missing required field: payload."}
   ```

3. **Save to DynamoDB** — a new item is written with a UUID, UTC timestamp, the payload
   value, and the caller's source IP.

4. **Respond** — 200 with:
   ```json
   {"status": "healthy", "message": "Request processed and saved."}
   ```

CloudWatch logs are queryable via **CloudWatch Logs Insights** in the AWS console.
Log group: `/aws/lambda/{env}-health-check-function` (e.g. `/aws/lambda/staging-health-check-function`).
Retention is 7 days for staging, 30 days for prod.

---

## Prerequisites

### Tools
- Terraform ≥ 1.6
- AWS CLI (for bootstrapping only — CI uses OIDC, no stored keys)

### GitHub Secrets
Three secrets must be set in the repository before the pipelines can run:

| Secret | What it is |
|---|---|
| `STAGING_DEPLOY_ROLE_ARN` | ARN of `staging-ci-deployment-role` (created by Terraform) |
| `PROD_DEPLOY_ROLE_ARN` | ARN of `prod-ci-deployment-role` (created by Terraform) |
| `ALERT_EMAIL` | Email address for billing alerts |

The role ARNs are output by `terraform apply`. `ALERT_EMAIL` is injected as
`TF_VAR_alert_email` in CI so the address is never committed to the repository.

### Terraform Variables
Each environment has a `.tfvars` file with all non-secret configuration.
`staging.tfvars` and `prod.tfvars` set environment name, region, budget limit,
throttle limits, log retention, and the S3 bucket used for Lambda packages.
`alert_email` is the only variable not in the tfvars files — it comes from the
GitHub secret above.

---

## CI/CD Pipeline

Two workflows handle deployments. Both use **GitHub OIDC** — no long-lived AWS
access keys are stored anywhere. GitHub mints a signed JWT per run; AWS verifies it
and issues temporary STS credentials scoped to that job.

### Staging — `deploy-staging.yml`

Triggers automatically on push to `main` when `terraform/` or `lambda/` files change.
Three jobs run in sequence:

```
package  →  plan  →  apply
```

1. **Package** — `pip-audit` scans Lambda dependencies for CVEs, then builds a
   self-contained zip and uploads it to S3:
   `s3://devops-hw-terraform-state/lambda-packages/staging/run{N}-{sha}/function.zip`

2. **Plan** — Checkov scans the Terraform for IaC misconfigurations (fails on findings),
   then `terraform plan -out=tfplan` is run and the plan file is uploaded as a
   workflow artifact. Nothing in AWS changes yet.

3. **Apply** — pauses at the `staging` GitHub Environment gate for approval,
   downloads the exact artifact from the plan job, runs `terraform apply tfplan`.
   The apply executes the frozen plan — it cannot drift from what was reviewed.

### Prod — `deploy-prod.yml`

Manual only (`workflow_dispatch`). Same package → plan → apply sequence in a single job,
gated by the `prod` GitHub Environment approval before anything runs.

---

## Pull Request Workflow

The `main` branch is protected — direct pushes are blocked. All changes reach `main`
through a pull request.

### Creating a branch and opening a PR

```bash
git checkout -b my-feature
# make changes
git add .
git commit -m "feat(terraform): ..."
git push -u origin my-feature
```

Then open a pull request targeting `main` on GitHub.

### What runs automatically on every PR

As soon as a PR is opened (or new commits are pushed to it), the **PR Validation**
workflow (`pr-validate.yml`) starts automatically — no manual trigger needed. It runs
only when `terraform/` or `lambda/` files changed; docs-only PRs are skipped.

The single `Scan & validate` job does four things in sequence, with no AWS credentials:

```
pip-audit  →  terraform init (no backend)  →  terraform fmt -check  →  checkov
```

| Step | What it catches |
|---|---|
| `pip-audit` | Known CVEs in Lambda Python dependencies |
| `terraform fmt -check` | Formatting drift — fails if any `.tf` or `.tfvars` file isn't canonical |
| `terraform validate` | Syntax errors, type mismatches, bad references |
| `checkov` | IaC misconfigurations (same skip list as the deploy workflows) |

The job result appears as a status check on the PR — a green tick or a red cross next
to the commit SHA.

### Merge gates

Before GitHub allows the merge button to turn green:

1. **PR Validation must pass** — the `Scan & validate` status check is required.
2. **At least one reviewer must approve** — configured in branch protection rules.
3. **Stale approvals are dismissed** — pushing a new commit to the PR clears previous
   approvals and requires a fresh review.

### After merge

Merging into `main` triggers `deploy-staging.yml` (if `terraform/` or `lambda/` files
changed). The staging pipeline runs exactly the same scans again, then plans, then
waits for environment approval before applying — so every infrastructure change is
scanned twice: once on the PR branch, once post-merge before it reaches AWS.

---

## Triggering a Staging Deployment

1. Make a change to any file in `terraform/` or `lambda/`
2. Commit and push to `main`
3. GitHub Actions starts the pipeline automatically — visible under **Actions** in the repository
4. The `package` and `plan` jobs run without any interaction
5. When the `apply` job is pending, go to **Actions → the running workflow → Review deployments**
6. Approve the `staging` environment gate
7. `terraform apply` runs against the frozen plan

To re-deploy without a code change (e.g. to pick up a Terraform variable update),
push any change to a file in `terraform/` — or trigger the workflow manually from the
Actions tab using **Run workflow**.

---

## Testing the Endpoint

The invoke URL is printed by `terraform output invoke_url` after apply, or find it in
the AWS console under API Gateway → your API → Invoke URL.

**Staging:** `https://rtwa5sti6d.execute-api.us-east-1.amazonaws.com/health`  
**Prod:** `https://8bql4tbsd3.execute-api.us-east-1.amazonaws.com/health`


**Staging Example**
```bash
INVOKE_URL=https://rtwa5sti6d.execute-api.us-east-1.amazonaws.com/health

# Healthy request — expect 200
curl -s -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"payload": "hello"}' | jq
# {"status": "healthy", "message": "Request processed and saved."}

# Missing payload — expect 400
curl -s -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{}' | jq

# Invalid JSON — expect 400
curl -s -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d 'not-json' | jq
```

The smoke test workflow (`API Smoke Test`) runs six cases against both environments
in parallel — trigger it manually from the Actions tab.

---

## Design Choices

**OIDC instead of IAM user keys.** Static access keys are permanent — if they leak
you have to rotate them and hope nobody used them. OIDC tokens expire when the job
ends and are cryptographically bound to a specific repo, branch, and environment.
The staging role only accepts tokens from pushes to `main` or jobs in the `staging`
environment; the prod role only accepts jobs in the `prod` environment. A push to
`main` cannot assume the prod role. (Production credentials are isolated from 
automatic staging deployments.)

**S3-backed Lambda packages with versioned keys.** The pipeline builds the zip and
uploads it as `lambda-packages/{env}/run{N}-{sha}/function.zip` before Terraform runs.
Terraform just points Lambda at the S3 object. Every deploy is a distinct, traceable
artifact — rollback is a one-line `s3_key` change. The version string is stored as
the Lambda function's `description` so you can see what's deployed in the AWS console.

**Frozen plan artifact.** The `plan` job uploads the plan file; the `apply` job
downloads and runs it. This means the apply executes exactly what was reviewed —
no re-planning against potentially drifted state between the two jobs.

**No wildcards in IAM resource ARNs.** The Lambda execution role can write to its
own log group and its own DynamoDB table — nothing else. The CI deployment role
lists every action Terraform actually calls and scopes each statement to the exact
resource ARNs this project manages.

**`PAY_PER_REQUEST` DynamoDB.** No capacity planning, scales to zero, cost-efficient
for low-traffic workloads. SSE enabled (required by the spec, also costs nothing).
PITR enabled — cheap and makes table recovery possible if something goes wrong.

**Plan and apply both run inside GitHub Actions, never locally.** The OIDC trust
policies are locked to specific GitHub Actions contexts — the staging role only
accepts tokens from CI jobs, not from a developer's local AWS CLI session. This is
deliberate. Running `terraform apply` locally with personal credentials bypasses the
approval gate, skips the Checkov and pip-audit scans, and leaves no audit trail.
By keeping all Terraform execution inside the pipeline, every change to infrastructure
goes through the same path: scanned, planned, reviewed, approved, applied. The plan
output is visible in the GitHub Actions run log before anyone clicks approve — so the
person approving actually sees what will change, not just a green checkmark.

**HTTP API (APIGatewayV2) over REST API.** Lower cost, lower latency, much less
configuration for a Lambda proxy. Throttling is configured at the stage level with
separate limits per environment (staging: 10 req/s / burst 20, prod: 100/200).

**Staging auto-deploys; prod is always manual.** The `paths` filter on the staging
trigger means docs-only pushes don't kick off a full deploy pipeline. Prod stays
`workflow_dispatch` regardless — there's no scenario where production should deploy
without a human decision.

**S3 remote state with per-environment keys.** Terraform state lives in
`s3://devops-hw-terraform-state` under separate keys (`staging/terraform.tfstate`,
`prod/terraform.tfstate`) so the two environments can never overwrite each other's
state. S3 native locking (`use_lockfile = true`) prevents concurrent applies without
needing a separate DynamoDB lock table. The bucket has versioning enabled — if state
gets corrupted, the previous version is one S3 restore away.

**Billing alerts on both environments.** `aws_budgets_budget` sends email at 80% and
100% of the monthly limit — staging at $6, prod at $11. Account-scoped, so a surprise
charge from any service shows up, not just the ones this project creates. Configured
before touching anything else so there's no window where runaway costs go unnoticed.

**Resource tagging on everything.** Every resource carries `Environment`, `Project`,
and `ManagedBy = terraform` tags. Makes the billing console readable and makes
`terraform destroy` reliable — you can filter by tag to confirm exactly what will be
removed before running it.

**Explicit CloudWatch log group with retention.** Without a managed log group,
Lambda creates one automatically and logs accumulate indefinitely. Terraform owns the
log group resource, sets retention per environment (7 days staging, 30 days prod),
and the Lambda execution role is explicitly denied `logs:CreateLogGroup` — so Lambda
can only write to the group Terraform created.

**X-Ray tracing enabled on Lambda.** Active tracing adds per-invocation traces to
AWS X-Ray at minimal cost. Useful for debugging cold starts and latency spikes without
adding any instrumentation to the function code.
