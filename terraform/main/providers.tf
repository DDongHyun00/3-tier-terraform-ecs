# 자격 증명은 환경에서 온다. 로컬: AWS_PROFILE=3tier(SSO), CI: OIDC로 수임한 역할.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "3-tier-terraform-ecs"
      Env     = var.env
      Owner   = "DDongHyun00"
    }
  }
}
