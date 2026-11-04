# 자격 증명: 로컬 AWS_PROFILE=3tier(SSO), CI는 Environment staging 잡이 OIDC로 3tier-github-deploy-staging을 수임한다(DEC-63)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "3-tier-terraform-ecs"
      Env     = "staging"
      Owner   = "DDongHyun00"
    }
  }
}
