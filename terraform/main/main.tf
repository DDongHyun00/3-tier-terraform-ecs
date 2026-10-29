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
# 전제: 가장 최근 이미지에 태그가 있어야 한다(아래 postcondition). ECR이 비어 있으면 첫 apply 전에 deploy로 이미지를 올린다.
data "aws_ecr_image" "board_latest" {
  repository_name = data.aws_ecr_repository.board.name
  most_recent     = true

  lifecycle {
    postcondition {
      condition     = length(self.image_tags) > 0
      error_message = "3tier/board의 가장 최근 이미지에 태그가 없다. 태그(커밋 SHA 앞 7자리)가 있는 이미지를 push한 뒤 다시 실행한다. deploy.yml은 provenance: false라 태그 없는 이미지를 만들지 않는다. 수동으로 push할 때는 docker buildx build --provenance=false로 빌드한다."
    }
  }
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# 알람 토픽은 bootstrap에 있다(Q Developer 구독이 destroy로 사라지지 않게, #38). 없으면 plan이 여기서 멈춘다
data "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
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

module "observability" {
  source = "../modules/observability"

  name_prefix = local.name_prefix
  region      = var.region

  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  cluster_name            = module.compute.cluster_name
  service_name            = module.compute.service_name
  db_identifier           = module.data.db_identifier

  alarm_topic_arn = data.aws_sns_topic.alarms.arn
}
