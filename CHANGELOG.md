# Changelog

This is a running log of every commit — what changed, why I did it that way, and anything that bit me along the way.

---

## `16c096f` — initial commit
Initial repository setup.

---

## `9e006a6` — initialize project structure and gitignore
Set up the folder layout: `lambda/`, `terraform/`, `.github/workflows/`. The `.gitignore` was the important part — `.terraform/`, `*.zip`, and `terraform.tfstate*` all need to stay out of git. State files can contain secrets, and the zip gets regenerated anyway.

---

## `bdedb26` — tf: add billing spend alert to protect the account
Added billing alerts before provisioning billable AWS resources. `aws_budgets_budget` sends email at 80% and 100% of the monthly limit. I set staging to $6 and prod to $11 — prod gets a bit more room but not much, it's still a homework project. The alert is account-scoped so it catches surprise charges from any service, not just this one.

---

## `9ef965d` — tf: configure S3 remote state backend with DynamoDB locking
Keeping `terraform.tfstate` locally is asking for trouble — you lose it, accidentally commit it, or two people overwrite each other. Moved state to S3 with a separate key per environment (`staging/terraform.tfstate`, `prod/terraform.tfstate`) so they never touch each other. Used `use_lockfile = true` which is the newer S3 native locking — had to remove the old `dynamodb_table` backend argument later when I noticed it was deprecated.

---

## `17c3607` — tf: fixed prod env - email
Wrong email in `prod.tfvars`. Fixed it. (had to hide it - Nothing to see there)

---

## `a483a85` — tf: add IAM roles with least-privilege permissions
Two roles here. 

The **lambda execution role** only lets the function write logs to its own log group and write items to its own DynamoDB table. No wildcards, exact ARNs everywhere. If the function somehow gets compromised it can't touch anything else.

The **CI deployment role** is what Terraform runs as in the pipeline. At this point it trusted a specific IAM user (`cli-user`) — that got replaced with OIDC later. I used `data "aws_caller_identity"` to pull the account ID at plan time instead of hardcoding it, since that would be a security issue.

---

## `89abe3d` — lambda: implement health check handler with input validation
The actual Lambda code. The validation chain is:
1. Is the body valid JSON? If not → 400
2. Does `payload` key exist? If not → 400  
3. Is `payload` non-null and non-empty? If not → 400
4. Write to DynamoDB, return 200

I put the boto3 DynamoDB client outside the handler so it gets reused across warm invocations — otherwise you're paying to recreate the connection on every call. `TABLE_NAME` comes from an environment variable that Terraform injects, so the code doesn't care which environment it's running in.

---

## `6e3f09d` — fix-tf: replace deprecated dynamodb_table with S3 native locking
Terraform 1.6 added native S3 locking so you don't need a separate DynamoDB table for it anymore. Removed the old `dynamodb_table` backend argument that was throwing deprecation warnings.

---

## `48ac302` — tf: provision DynamoDB table with server-side encryption
`PAY_PER_REQUEST` billing mode — no capacity planning, scales to zero when nothing is happening, cost-effective for low-volume workloads. SSE enabled because the project security rules require it and it costs nothing extra. The hash key is `id`, a UUID generated per request.

---

## `62dd11f` — tf: add Lambda function resource with local packaging
Used Terraform's `archive_file` data source to zip the `lambda/` folder at plan time. The nice part is `source_code_hash` — Terraform compares the zip hash on every apply and only redeploys if the code actually changed. No manual uploads, no forgetting to redeploy after a code change.

---

## `c02297b` — tf: add throttling variables for API Gateway rate limiting
Pulled throttle limits into variables before creating the API Gateway, so staging and prod can have different limits. Staging is 10 req/s with a burst of 20. Prod is 100/200. This prevents a runaway client from generating a surprise AWS bill.

---

## `e6b1632` — tf: add API Gateway HTTP API with Lambda integration and throttling
Went with HTTP API (APIGatewayV2) instead of REST API — it's cheaper, lower latency, and much less config for a simple Lambda proxy. The integration uses `AWS_PROXY` with payload format `2.0` which is the current standard. Both `GET /health` and `POST /health` route to Lambda. The Lambda permission is scoped to exactly that path so nothing else can invoke the function via the gateway.

---

## `4f334e1` — lambda-fix: clean up payload validation logic
The original validation only caught the missing key case cleanly. Added explicit checks for `None` and empty string so `{"payload": null}` and `{"payload": ""}` both return 400 with a clear error message instead of falling through.

---

## `9540923` — fix-tf: add log retention, Lambda timeout, remove dead IAM statement
A few things I missed:
- Without an explicit `aws_cloudwatch_log_group` resource, Lambda creates the log group itself and logs never expire. Added it with a `retention_in_days` variable.
- Lambda's default timeout is 3 seconds. That's fine normally but too tight with cold starts, so I added a `lambda_timeout` variable (default 30 s).
- Removed an IAM statement that referenced a resource I'd already deleted.

---

## `3a3a247` — fix: commit provider lock file and remove stale gitkeeps
`.terraform.lock.hcl` needs to be in git. Without it, `terraform init` in CI might pull a newer AWS provider version that has breaking changes. Pinning it means everyone — local and CI — gets identical provider binaries. Also cleaned up the empty `.gitkeep` files since the folders had real content now.

---

## `1d4a0a0` — refactor-tf: type-safe variables, tighten version constraint, validate environment input
Added `type` to every variable so Terraform catches wrong input types at plan time. Added a `validation` block to `environment` — if you pass anything other than `"staging"` or `"prod"` it fails immediately with a readable error. Tightened `required_version` to `~> 1.6` to prevent someone from accidentally running this on a very different Terraform version.

---

## `69584ea` — fix-tf: add environment tags to all resources
Forgot to tag things. Added `local.common_tags` (`Environment`, `Project`, `ManagedBy`) to every taggable resource. Useful when looking at the billing console and wondering which resources belong to what.

---

## `31b332a` — tf: add GitHub Actions OIDC identity provider
This was the most interesting design decision. The original plan used an IAM user (`cli-user`) with static access keys stored in GitHub secrets. Static keys work, but they introduce long-lived credential risk. — if they ever leak you have to rotate them and hope nobody used them in the meantime.

OIDC is cleaner: GitHub mints a signed JWT for each workflow run, AWS verifies it against the registered identity provider, and issues temporary STS credentials that expire when the job ends. No keys to store, no keys to rotate, no keys to leak.

The OIDC provider (`token.actions.githubusercontent.com`) is an account-level resource — only needs to exist once. I created it in staging (`create_oidc_provider = true`) and have prod skip creating it (`false`) but still resolve the ARN by constructing it from the account ID. Both environments end up with the provider ARN available via a local.

---

## `5d581fb` — tf: update CI deployment role to trust GitHub OIDC
Updated the trust policy on the CI role to accept the OIDC token instead of the IAM user.

The key part is the `sub` condition — it locks down exactly which workflow can assume the role:
- staging role only accepts tokens from a push to `main` in this specific repo
- prod role only accepts tokens from a run in the `prod` GitHub Environment

Without the `sub` condition, any GitHub Actions workflow anywhere could potentially assume the role as long as it had OIDC enabled. The condition is what makes it actually secure.

---

## `42fbe0f` — ci: add OIDC smoke-test workflow
Before writing the real deploy workflows I wanted to confirm OIDC actually worked end-to-end. Added a tiny `workflow_dispatch` job that just assumes the staging role and runs `aws sts get-caller-identity`. Triggered it manually, got back the assumed role ARN — everything wired up correctly.

---

## `7e98996` — ci: add API smoke test workflow
Simple workflow to hit the live staging endpoint with curl and check status codes. No AWS credentials needed — it's a public HTTPS endpoint. Runs in a few seconds.

One thing I got wrong initially: I assumed `GET /health` would return 405 since POST is the intended method. It actually returns 400 because API Gateway HTTP API routes all matched methods to Lambda rather than rejecting at the gateway level — Lambda receives the GET, finds no `payload`, and returns 400 itself. Fixed the assertion.

---

## `5e2e893` — ci: add body assertion and edge-case smoke tests
Expanded from 3 tests to 6. Added `null` payload and malformed JSON cases since the Lambda handler explicitly handles both. Also added a body content check on the 200 response — `jq -e '.status == "healthy"'` — because just checking the status code doesn't prove the function returned the right thing.

---

## `fc63d0d` — fix-ci: correct GET method smoke test to expect 400
Follow-up from the GET method discovery above. Changed the assertion from 405 to 400.

---

## `94cdabd` — ci: add staging workflow — OIDC auth and terraform init

First real CI workflow. Chose OIDC over long-lived IAM user keys from the start — the staging role already existed from the previous OIDC plumbing, so wiring it up here was straightforward. The `role-duration-seconds: 3600` gives enough headroom for a slow Terraform apply without being excessive. Terraform init runs with the explicit backend key so the workflow always touches the staging state file and never the prod one, regardless of which environment later steps target.

---

## `c6a6ec1` — ci: add Checkov IaC security scan to staging workflow

Added Checkov as the IaC security gate using `bridgecrewio/checkov-action@v12`. The scan runs before `terraform plan` so a finding fails the workflow before any infrastructure is touched. `soft_fail: false` makes failures blocking rather than advisory — a misconfigured resource should never reach plan, let alone apply.

---

## `9000015` — fix-terraform: resolve Checkov findings - PITR, X-Ray, concurrency, route auth

Checkov's first run found several real gaps. Enabled PITR on the DynamoDB table — point-in-time recovery is cheap and the right default for any table that holds request data. Enabled X-Ray active tracing on Lambda — useful for debugging latency and surfacing cold-start behaviour. Added the throttling configuration to the API Gateway stage — limits were already in variables, they just weren't wired to the stage resource.

---

## `411c559` — fix-ci: skip CKV_AWS_309 - public endpoint by design, document all skips

`CKV_AWS_309` requires a non-NONE auth type on the API route. The health-check endpoint is intentionally unauthenticated — adding IAM or JWT auth would break the smoke tests and contradict the spec. Added the check to the skip list with a comment so a future reader understands it's a deliberate choice, not an oversight. All other skipped checks are similarly documented inline.

---

## `27cc057` — ci: add terraform plan to staging workflow

Added `terraform plan -var-file="staging.tfvars" -out=tfplan` as the last step in the (then-single-job) workflow. Saving the plan to a file is important: it freezes exactly what will be applied so the apply step can't drift from what was reviewed. The `TF_VAR_alert_email` env var is set here from the GitHub secret so the variable is never committed to the repository.

---

## `458bb22` — fix-terraform: add missing lambda_concurrent_executions to staging.tfvars

The `lambda_concurrent_executions` variable existed in `variables.tf` but had no entry in `staging.tfvars`, causing Terraform to use the default. Added it explicitly so the value is visible and intentional in the var file rather than silently inherited.

---

## `bfbde79` — fix-tf: disable reserved concurrency — account limit equals AWS minimum

Setting any positive reserved concurrency value caused Terraform apply to fail: the AWS account's total concurrent execution limit is 10, which is exactly the AWS-enforced minimum for unreserved concurrency. Reserving even 1 execution would push unreserved below the minimum. Set `lambda_concurrent_executions = -1` in both tfvars files to disable the reservation and added `CKV_AWS_115` to the Checkov skip list with an explanation, since Checkov flags the absence of a reserved limit as a finding.

---

## `4c4d879` — fix-tf: tighten IAM roles — drop redundant lambda log perm, add missing CI permissions

Removed `logs:CreateLogGroup` from the Lambda execution role — Terraform owns the log group resource, so Lambda should never need to create it. A CloudWatch Logs log group created by Lambda itself would be unmanaged and could persist after `terraform destroy`. Added the permissions the CI deploy role was missing in practice: several `Describe*`, `List*`, and tag-management actions that Terraform's AWS provider calls during plan and apply.

---

## `0fb89cc` — fix-tf: split DescribeLogGroups to broader scope — list action requires root ARN

`logs:DescribeLogGroups` was scoped to the specific log group ARN, which caused an AccessDenied during plan. List-style IAM actions for CloudWatch Logs require the resource ARN to be `arn:aws:logs:region:account:log-group:*` — they don't support resource-level restriction at the individual log group level. Split the statement into two: one with the broader ARN for `DescribeLogGroups`, one with the specific ARN for all other log actions.

---

## `3dfa2f3` — fix-tf: add log group ARN without wildcard for ListTagsForResource

`logs:ListTagsForResource` was still failing. The action requires the exact log group ARN without the `:*:*` stream suffix — providing an ARN with a wildcard causes IAM to reject it. Added a second ARN (without the trailing `/*`) to the resource list of the specific-scope statement so both the log group itself and its log streams are covered by the appropriate actions.

---

## `81b0674` — fix-tf: add missing lambda GetFunctionCodeSigningConfig permission

Terraform's Lambda resource calls `GetFunctionCodeSigningConfig` during plan to read the current state, even when code signing is not in use. The CI deploy role was missing this action, causing plan to fail with AccessDenied. Added it to the `ManageLambda` statement alongside the other Lambda read permissions.

---

## `a8d58a5` — ci: add pip-audit Lambda dependency scan

Added `pip-audit -r lambda/requirements.txt` before the Checkov scan. Checkov covers the infrastructure; pip-audit covers the Python dependencies that actually run inside the Lambda. The `--skip-editable` flag avoids a spurious error when there are no editable installs in the requirements file. Both security gates now run before any Terraform operation.

---

## `5d8faab` — fix-tf: remove REDACTED alert_email from tfvars — use TF_VAR_alert_email from GitHub secret

Discovered that a `-var-file` value takes precedence over the `TF_VAR_*` environment variable for the same variable. The `alert_email` in the tfvars files was shadowing the secret passed from CI. Removed the key from both `staging.tfvars` and `prod.tfvars` entirely — the only source of truth is now the `ALERT_EMAIL` GitHub secret, passed as `TF_VAR_alert_email` in the workflow. This also means the email address is never committed to the repository.

---

## `3e4afd8` — ci: split staging workflow into plan + gated apply

Restructured the staging workflow from a single job into two: `plan` and `apply`. The plan job runs all the checks (pip-audit, Checkov, terraform plan) and uploads the plan file as a workflow artifact. The apply job downloads that artifact and runs `terraform apply tfplan` — it can only apply exactly what was planned. The apply job uses `environment: staging`, which creates an approval gate in GitHub Environments. This mirrors the prod workflow pattern and gives a human checkpoint before any infrastructure actually changes.

---

## `aa06fe2` — fix-tf: allow both branch and environment OIDC sub claims for staging

Jobs that reference a GitHub Environment get a different OIDC `sub` claim than jobs that don't. The `plan` job (no environment) gets `repo:org/repo:ref:refs/heads/main`; the `apply` job (uses `environment: staging`) gets `repo:org/repo:environment:staging`. The IAM role's trust policy originally only accepted the branch-based form, so the apply job was always rejected. Changed `github_oidc_sub` in the staging path to a list containing both forms — IAM `StringLike` with a list accepts a token that matches any entry.

---

## `d473362` — tf: switch Lambda deployment to S3-backed package

Replaced the `archive_file` data source with S3-based deployment. Previously Terraform would zip the `lambda/` folder at plan time and upload it inline — that meant the package was built locally, never versioned, and any code change required the person running Terraform to have the right Python environment available.

The new model: CI builds and uploads the zip before Terraform runs, Terraform just points Lambda at the S3 object. Three new variables handle this — `lambda_s3_bucket` (static, in tfvars), `lambda_s3_key` and `lambda_version` (dynamic, injected as `TF_VAR_*` from the pipeline on each run). The version string (`run{N}-{sha}`) is stored as the Lambda function's `description` so it's visible in the console without digging through S3 or GitHub Actions logs.

Also added `publish = true` here — that turned out to be a mistake (see the two fix commits below).

---

## `cc7ad9f` — ci: add Lambda package job to staging workflow

Added a `package` job as the first step in the staging pipeline, running before `plan`. It:
1. Scans dependencies with pip-audit (moved from the `plan` job — makes more sense to scan before building)
2. Computes the version string: `run${{ github.run_number }}-$(git rev-parse --short HEAD)`
3. `pip install -r requirements.txt -t build/` then zips everything — produces a self-contained package Lambda can run without a layer
4. Uploads to `s3://devops-hw-terraform-state/lambda-packages/staging/{version}/function.zip`
5. Exposes `s3_key` and `version` as job outputs

The `plan` job gains `needs: package` and receives both outputs as `TF_VAR_lambda_s3_key` and `TF_VAR_lambda_version`. The `apply` job is unchanged — the plan file already has the resolved S3 key baked in, so it applies exactly what was reviewed with no re-planning.

---

## `eee5ef8` — ci: add prod deploy workflow with Lambda packaging

First committed version of `deploy-prod.yml`. The file existed locally for a while but was never staged. Committed it here with the packaging steps already included so prod and staging are consistent from the start.

Prod stays as a single job (no separate plan+apply artifacts) since the `environment: prod` gate already forces a manual approval before anything runs. The job saves the plan to `tfplan` and applies from it — same drift-prevention benefit as staging without needing a second job. The Lambda package uses the same version scheme as staging but under the `lambda-packages/prod/` S3 prefix.

---

## `789eb6f` — fix-tf: add versioned Lambda ARN to CI role for publish support

`publish = true` on the Lambda resource causes Terraform to call `GetFunctionConfiguration` on the versioned ARN (e.g. `function:staging-health-check-function:1`) after the function updates. The CI role's `ManageLambda` statement only covered the unversioned ARN, so every apply failed with a 403 on that call. Added a second resource entry with the `:*` qualifier to cover all published versions.

This resolved the initial permission issue but revealed a second deployment problem.

---

## `1db7d20` — fix-tf: remove publish=true — S3 key versioning is sufficient

The versioned ARN fix resolved the permission error, but the next run hit a race condition: Terraform parallelises resource updates, so the IAM policy and the Lambda function were modified at the same time. The IAM change finished in ~0s but IAM propagation takes several seconds — by the time Lambda called `GetFunctionConfiguration` on `:2`, the new policy still hadn't propagated and the 403 came back.

The root cause is that `publish = true` was never necessary. The S3 key already encodes the full version (`run{N}-{sha}`) — every deploy is a distinct, traceable artifact. AWS Lambda's built-in versioning adds nothing here except IAM complexity and a propagation race. Removed `publish = true` and reverted the versioned ARN addition from the previous commit.

---

## `698bd34` — ci: expand smoke test to cover both staging and prod

Rewrote the smoke test workflow as a matrix job covering both staging and prod in parallel. `fail-fast: false` means one environment failing doesn't cancel the other — you see the full picture in a single run. The job name includes `${{ matrix.env }}` so the two runs are labelled clearly in the GitHub Actions UI rather than both appearing as "Smoke test".

---

## `d925ebd` — fix-ci: align prod Checkov skip list with staging

The prod workflow was committed with only 2 Checkov skips (`CKV_AWS_272`, `CKV2_AWS_29`) while staging had 10. Every check Checkov runs against the staging Terraform also runs against prod — the same intentional design decisions (public endpoint, no VPC, account concurrency limit, etc.) apply equally to both environments. Copied the full skip list from staging to prod and added a comment pointing to staging where each suppression is documented.

---

## `5f90e67` — ci: only trigger staging deploy on terraform or lambda changes

Added a `paths` filter to the staging deploy trigger. Previously any push to `main` — docs, changelog, workflow tweaks — kicked off the full package → plan → apply pipeline. Now only changes under `terraform/` or `lambda/` trigger a deploy. A docs-only push no longer burns CI minutes or prompts an unnecessary environment approval click. The prod workflow is unaffected: it stays `workflow_dispatch` only.

---

## `b68e761` — fix-tf: remove PublishVersion from CI role, fix stale OIDC comment

Two small housekeeping fixes in `iam.tf`. First: `lambda:PublishVersion` was still listed in the CI deployment role's `ManageLambda` statement even though `publish = true` was removed two commits earlier (`1db7d20`). Dead permission — removed. Second: the comment block above the CI role still said "Trusted by the IAM user whose access key is stored in GitHub secrets" — that was accurate months ago but the role switched to OIDC in `5d581fb`. Updated the comment to reflect reality.

---

## `567f102` — ci: move invoke URLs to repo variables — keep endpoints out of source

The smoke test workflow had the raw API Gateway invoke URLs hardcoded in the YAML. That's fine while the endpoints are stable but it means every destroy-and-recreate requires a source edit and a commit just to update a URL. Replaced both with GitHub repository variables — `${{ vars.STAGING_INVOKE_URL }}` and `${{ vars.PROD_INVOKE_URL }}`. The actual URLs now live in GitHub Settings → Secrets and variables → Variables, updated out-of-band whenever the API Gateway IDs change. Source stays clean.

---

## `92eef6d` — tf: clarify oidc comment

Minor comment fix in `oidc.tf`. The existing comment said "We create it when applying staging" twice in slightly different ways after a botched edit. Cleaned it up to a single clear sentence: staging creates the provider, prod resolves the ARN by construction.

---

## `de5c5ee` — ci: FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true — remove warning

GitHub Actions is deprecating the Node.js 20 runtime for actions on June 2nd, 2026. Several third-party actions in the pipeline (actions/checkout, actions/upload-artifact, etc.) still declare `runs-with: node20` internally. Adding `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a workflow-level env variable opts all jobs in that workflow into the Node.js 24 runner immediately, eliminating the deprecation warning before the forced cutover. Applied to all three workflows: `deploy-staging.yml`, `deploy-prod.yml`, and `smoke-test.yml`.

---

## `0a51ed4` — ci: extend oidc smoke test — list deployed Lambda packages from S3

Extended `oidc-test.yml` with a second step that uses the already-assumed OIDC credentials to query the S3 state bucket and list every Lambda deployment package stored under `lambda-packages/staging/` and `lambda-packages/prod/`. Output includes file size, upload date, and the `run{N}-{sha}` version string for each zip — a full deployment history for both environments in one workflow run. No additional permissions needed; the staging deploy role already has S3 read access to the state bucket.

---

## `2689594` — ci: add PR validation workflow

Added `pr-validate.yml` — a lightweight validation workflow that runs on every pull request targeting `main` when `terraform/` or `lambda/` files change. No AWS credentials are needed; the job uses `-backend=false` to init Terraform without touching S3.

Four checks run in sequence in a single `Scan & validate` job:
1. `pip-audit` — scans Lambda dependencies for known CVEs
2. `terraform fmt -check -recursive` — fails if any `.tf` or `.tfvars` file has formatting drift
3. `terraform validate` — catches syntax errors, type mismatches, and broken references
4. `checkov` — IaC security scan with the same skip list as the deploy workflows

The job name `Scan & validate` is used as the required status check in branch protection — PRs can't be merged until this passes. Combined with the `push`-to-`main` trigger on `deploy-staging.yml`, every infrastructure change is scanned twice: once on the PR branch before merge, and again post-merge before it reaches AWS.
