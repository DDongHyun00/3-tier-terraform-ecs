terraform {
  required_version = ">= 1.11"

  # bootstrap이 만든 버킷. bootstrap과는 다른 key를 쓴다.
  backend "s3" {
    bucket       = "3tier-tfstate-1136"
    key          = "main/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
