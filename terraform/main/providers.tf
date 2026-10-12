provider "aws" {
  region  = var.region
  profile = "3tier"

  default_tags {
    tags = {
      Project = "3-tier-terraform-ecs"
      Env     = var.env
      Owner   = "DDongHyun00"
    }
  }
}
