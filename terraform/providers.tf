terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State is stored per environment — pass the key at init time:
  #   terraform init -backend-config="key=staging/terraform.tfstate"
  #   terraform init -backend-config="key=prod/terraform.tfstate"
  backend "s3" {
    bucket       = "devops-hw-terraform-state"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

}

provider "aws" {
  region = var.aws_region
}
