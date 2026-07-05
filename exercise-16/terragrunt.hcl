# Terragrunt Configuration for EKS Cluster Deployment

inputs = {
  aws_region  = "ap-south-1"
  environment = "production"
}

# Remote state management in S3
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "my-company-production-tfstate"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }
}
