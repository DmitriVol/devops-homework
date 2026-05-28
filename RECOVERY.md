## Known Issues

**`terraform destroy` can leave a stale S3 lock file.**
If a `terraform destroy` run is interrupted mid-execution (process killed, pipe closed,
network drop), the S3 native lock file is not cleaned up. Subsequent Terraform commands
fail with `Error: Error acquiring the state lock`. Fix:
```bash
aws s3 rm s3://devops-hw-terraform-state/staging/terraform.tfstate.tflock
# or for prod:
aws s3 rm s3://devops-hw-terraform-state/prod/terraform.tfstate.tflock
```
Only do this if you are certain no other Terraform process is running.

**Rebuilding after a full destroy requires bootstrapping Lambda before re-apply.**
A full destroy wipes the S3 Lambda packages. The next `terraform apply` will fail
immediately because the Lambda resource references an S3 key that no longer exists.

Destroy order matters: destroy staging first. The OIDC provider is created by the
staging apply (`create_oidc_provider = true`); prod only resolves its ARN. Destroying
staging removes the provider cleanly. Destroying prod first leaves it orphaned.

After destroy, before applying either environment, upload a bootstrap package:
```bash
mkdir -p build && pip install -r lambda/requirements.txt -t build/
cp lambda/handler.py build/
cd build && zip -r ../function.zip . && cd ..
aws s3 cp function.zip s3://devops-hw-terraform-state/lambda-packages/staging/bootstrap/function.zip
aws s3 cp function.zip s3://devops-hw-terraform-state/lambda-packages/prod/bootstrap/function.zip
```
Then apply with the bootstrap key:
```bash
TF_VAR_lambda_s3_key=lambda-packages/staging/bootstrap/function.zip \
  terraform apply -var-file="staging.tfvars"
```
After the first successful CI pipeline run the versioned key takes over and the
bootstrap path is no longer needed.