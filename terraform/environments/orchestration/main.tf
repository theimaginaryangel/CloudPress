provider "aws" {
  region = "us-east-1"
}

module "orchestration" {
  source = "../../modules/orchestration"
}

output "api_endpoint" {
  value = module.orchestration.api_endpoint
}

output "state_bucket" {
  value = module.orchestration.terraform_state_bucket
}

output "source_bucket" {
  value = module.orchestration.source_bucket
}
