# main 루트 모듈. modules/를 조립한다. 매일 destroy/apply하는 대상.

locals {
  name_prefix = "3tier-${var.env}"
}

module "network" {
  source = "../modules/network"

  name_prefix = local.name_prefix
  azs         = var.azs
  # CIDR은 모듈 기본값(docs/architecture.md 5.1) 그대로 쓴다.
}

module "data" {
  source = "../modules/data"

  name_prefix          = local.name_prefix
  db_subnet_ids        = module.network.db_subnet_ids
  db_security_group_id = module.network.db_security_group_id
  multi_az             = var.multi_az
  account_suffix       = var.account_suffix
}

# bootstrap이 만든 것들은 state가 다르므로 data 소스로 읽는다.
data "aws_ecr_repository" "board" {
  name = "3tier/board"
}

# 새로 apply할 때 ECR에 마지막으로 push한 이미지로 뜨게 한다(#65). 태그는 커밋 SHA 앞 7자리, 불변이라 이미지 하나에 하나다.
# 떠 있는 서비스는 deploy.yml이 바꾸고 Terraform은 서비스의 task_definition 변경을 무시한다(ignore_changes).
data "aws_ecr_image" "board_latest" {
  repository_name = data.aws_ecr_repository.board.name
  most_recent     = true
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

module "compute" {
  source = "../modules/compute"

  name_prefix = local.name_prefix
  region      = var.region

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id

  image  = "${data.aws_ecr_repository.board.repository_url}:${data.aws_ecr_image.board_latest.image_tags[0]}"
  db_url = "jdbc:postgresql://${module.data.db_endpoint}:${module.data.db_port}/${module.data.db_name}"

  db_secret_arn        = module.data.db_secret_arn
  assets_bucket_name   = module.data.assets_bucket_name
  assets_rw_policy_arn = module.data.assets_rw_policy_arn

  domain_name    = var.domain_name
  hosted_zone_id = data.aws_route53_zone.main.zone_id
}
