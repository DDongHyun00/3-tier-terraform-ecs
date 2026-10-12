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
}
