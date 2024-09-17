provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      owner = "cicd-demo"
    }
  }
}
