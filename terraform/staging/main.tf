# 스테이징 루트(E11 #101, DEC-42·60·63). 운영과 같은 모듈을 작은 값으로 호출하고 state를 따로 둔다(staging/).
# 평소에는 destroy해 두고 배포 흐름 시험·재측정 세션에만 만든다. 운영과의 차이:
# - VPC 10.1.0.0/16, 영역 NAT 1개(DEC-41)
# - 인스턴스 1대·태스크 1개, 자동 확장·알람 없음(observability 모듈 미사용)
# - 관제 에이전트·로그 라우터 없음(관제↔스테이징 피어링은 필요해지면 추가)
# - 이름 접두사 3tier-staging: 배포 역할(3tier-github-deploy-staging)과 boundary(3tier-staging-ecs-boundary)가 이 이름만 다룬다

locals {
  name_prefix = "3tier-staging"
}

module "network" {
  source = "../modules/network"

  name_prefix          = local.name_prefix
  vpc_cidr             = "10.1.0.0/16" # DEC-52: 운영 10.0, 스테이징 10.1, 관제 10.100
  azs                  = var.azs
  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  db_subnet_cidrs      = ["10.1.20.0/24", "10.1.21.0/24"]
  nat_mode             = "single"
}

module "data" {
  source = "../modules/data"

  name_prefix          = local.name_prefix
  db_subnet_ids        = module.network.db_subnet_ids
  db_security_group_id = module.network.db_security_group_id
  multi_az             = false
  account_suffix       = var.account_suffix
  assets_bucket_prefix = "3tier-staging-assets"
}

data "aws_ecr_repository" "board" {
  name = "3tier/board"
}

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

  name_prefix               = local.name_prefix
  region                    = var.region
  permissions_boundary_name = "3tier-staging-ecs-boundary"

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id

  network_egress_dependency_ids = module.network.private_egress_dependency_ids

  image  = "${data.aws_ecr_repository.board.repository_url}:${var.image_tag != "" ? var.image_tag : data.aws_ecr_image.board_latest.image_tags[0]}"
  db_url = "jdbc:postgresql://${module.data.db_endpoint}:${module.data.db_port}/${module.data.db_name}"

  db_secret_arn        = module.data.db_secret_arn
  assets_bucket_name   = module.data.assets_bucket_name
  assets_rw_policy_arn = module.data.assets_rw_policy_arn

  # staging.3tier.link: ACM 인증서·A 레코드가 운영 존 안에 따로 생긴다
  domain_name    = "staging.${var.domain_name}"
  hosted_zone_id = data.aws_route53_zone.main.zone_id

  # 작게: 인스턴스 1대·태스크 1개, 자동 확장 없음
  desired_count         = 1
  asg_min_size          = 1
  asg_max_size          = 2 # 롤링 배포(최대 200%) 때 새 태스크가 뜰 자리
  enable_metrics_agents = false
}
