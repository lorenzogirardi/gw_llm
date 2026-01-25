# Terraform Backend Configuration for Sandbox Environment
#
# Uses S3 for state storage with DynamoDB for locking
# Region: us-east-1 (same as infrastructure)

terraform {
  backend "s3" {
    bucket         = "stargate-llm-gateway-tfstate"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "stargate-llm-gateway-tfstate-locks"
  }
}
