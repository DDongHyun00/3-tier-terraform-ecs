terraform {
  required_version = ">= 1.11"

  # state를 bootstrap이 만든 S3 버킷에 둔다. 잠금은 S3 네이티브(.tflock), DynamoDB 없음.
  # backend 블록에는 변수를 쓸 수 없어 버킷 이름을 직접 적는다.
  backend "s3" {
    bucket       = "3tier-tfstate-1136"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "3tier"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}