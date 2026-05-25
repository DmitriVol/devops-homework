# Serverless Health Check API

A serverless health-check endpoint on AWS — Lambda + API Gateway + DynamoDB —
fully provisioned by Terraform with a GitHub Actions CI/CD pipeline.

---

## Architecture

_Diagram and explanation coming after infrastructure is complete._

---

## Prerequisites

_To be completed — will list AWS secrets, GitHub secrets, and S3 backend requirements._

---

## Environments

| Environment | Trigger | Approval |
|-------------|---------|----------|
| staging | push to `main` | automatic |
| prod | `workflow_dispatch` | manual reviewer |

---

## CI/CD Pipeline

_To be completed — pipeline explanation._

---

## Deploying Staging

_To be completed — step-by-step guide._

---

## Testing the Endpoint

```bash
# Healthy request
curl -X POST https://<invoke-url>/health \
  -H 'Content-Type: application/json' \
  -d '{"payload": "hello"}'

# Missing payload — expect 400
curl -X POST https://<invoke-url>/health \
  -H 'Content-Type: application/json' \
  -d '{}'
```

---

## Design Choices

_To be completed._

