provider "aws" {
  region  = "ap-northeast-2"
  profile = "3tier"

  default_tags {
    tags = {
      Project = "3-tier-terraform-ecs"
      Env     = "prod"
      Owner   = "DDongHyun00"
    }
  }
}