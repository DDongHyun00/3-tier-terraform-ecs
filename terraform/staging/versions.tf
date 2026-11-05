terraform {
  required_version = ">= 1.11"

  # 운영(main)과 같은 버킷, 다른 key(DEC-60). 스테이징 배포 역할은 staging/ 아래만 읽고 쓴다(DEC-63)
  backend "s3" {
    bucket       = "3tier-tfstate-1136"
    key          = "staging/terraform.tfstate"
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
