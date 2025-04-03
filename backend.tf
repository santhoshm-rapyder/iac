terraform {
  backend "s3" {
    bucket         = "poceloelo"   # Replace with your actual S3 bucket name
    key            = "terraform/state.tfstate"  # Path to store the Terraform state file
    region         = "ap-south-1"  # Replace with your AWS region
    encrypt        = true  # Enable encryption for security
  }
}
