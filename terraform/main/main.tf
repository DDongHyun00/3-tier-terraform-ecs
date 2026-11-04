# main 루트 모듈. modules/를 조립한다. 매일 destroy/apply하는 대상.

locals {
  name_prefix = "3tier-${var.env}"
}

module "network" {
  source = "../modules/network"

  name_prefix = local.name_prefix
  azs         = var.azs
  # CIDR은 모듈 기본값(docs/architecture.md 5.1) 그대로 쓴다. 10.0.0.0/16(DEC-52)
  nat_mode = "regional" # 리전 NAT 수동 모드, 2a·2c에 EIP 1개씩(DEC-41)
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

  # destroy 순서: 서비스·ASG가 사설 서브넷의 인터넷 경로(NAT·라우트·연결)보다 먼저 지워지게(#108)
  network_egress_dependency_ids = module.network.private_egress_dependency_ids

  image  = "${data.aws_ecr_repository.board.repository_url}:${data.aws_ecr_image.board_latest.image_tags[0]}"
  db_url = "jdbc:postgresql://${module.data.db_endpoint}:${module.data.db_port}/${module.data.db_name}"

  db_secret_arn        = module.data.db_secret_arn
  assets_bucket_name   = module.data.assets_bucket_name
  assets_rw_policy_arn = module.data.assets_rw_policy_arn

  domain_name    = var.domain_name
  hosted_zone_id = data.aws_route53_zone.main.zone_id

  # 앱 로그 → FireLens → 관제 VPC Elasticsearch(E12 #98). CloudWatch Logs에는 라우터 자신의 로그만 남는다
  enable_log_router             = true
  elasticsearch_host            = module.logging.elk_private_ip
  elasticsearch_user_secret_arn = module.logging.fluentbit_secret_arn
  log_index_prefix              = module.logging.log_index_prefix
}

module "observability" {
  source = "../modules/observability"

  name_prefix = local.name_prefix

  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  cluster_name            = module.compute.cluster_name
  service_name            = module.compute.service_name

  alarm_topic_arn = data.aws_sns_topic.alarms.arn
}

# ---------- 관제 VPC (E11 #91, DEC-37·40·52·53) ----------
# Prometheus·Grafana(#92)와 ELK(E12)가 들어가는 공용 서비스 VPC. main에 두어 세션마다 만들고 지운다.
# 이름 접두사 3tier-prod-mon: 배포 역할 권한 범위(3tier-prod-* 역할·인스턴스 프로필·비밀)를 넓히지 않으려고.
module "network_monitoring" {
  source = "../modules/network"

  name_prefix          = "${local.name_prefix}-mon"
  vpc_cidr             = "10.100.0.0/16"
  azs                  = var.azs
  public_subnet_cidrs  = ["10.100.0.0/24"] # 영역 NAT 자리(2a)만. 인바운드 입구는 없다
  private_subnet_cidrs = ["10.100.10.0/24", "10.100.11.0/24"]
  db_subnet_cidrs      = []

  nat_mode                    = "single" # 영역 NAT 1개(DEC-41)
  create_tier_security_groups = false
}

# 관제 ↔ 운영. 스테이징은 별도 루트(DEC-60)라 관제 ↔ 스테이징 피어링은 #101에서 만든다.
module "peering_monitoring_prod" {
  source = "../modules/vpc_peering"

  name = "${local.name_prefix}-pcx-mon-prod"

  requester_vpc_id          = module.network_monitoring.vpc_id
  requester_cidr            = module.network_monitoring.vpc_cidr
  requester_route_table_ids = module.network_monitoring.private_route_table_ids

  accepter_vpc_id          = module.network.vpc_id
  accepter_cidr            = module.network.vpc_cidr
  accepter_route_table_ids = module.network.private_route_table_ids
}

module "monitoring" {
  source = "../modules/monitoring"

  name_prefix = "${local.name_prefix}-mon"
  vpc_id      = module.network_monitoring.vpc_id

  target_instance_security_group_id = module.compute.instance_security_group_id
  target_app_security_group_id      = module.network.app_security_group_id
  peering_dependency_ids            = module.peering_monitoring_prod.route_ids

  # 관제 서버(#92, DEC-54·55·57·59)
  region          = var.region
  subnet_id       = module.network_monitoring.private_subnet_ids[0]
  target_asg_name = module.compute.asg_name

  network_egress_dependency_ids = module.network_monitoring.private_egress_dependency_ids

  # 앱 지표(#94): Cloud Map 존을 관제 VPC에 연결하고 그 이름으로 수집
  app_discovery_zone_id  = module.compute.app_discovery_zone_id
  app_discovery_dns_name = module.compute.app_discovery_dns_name

  # Grafana 알림 → 기존 알람 토픽 → Slack(#95)
  alarm_topic_arn = data.aws_sns_topic.alarms.arn

  # RDS 알림은 CloudWatch 알람에서 Grafana로 옮겼다(DEC-45·62)
  db_identifier = module.data.db_identifier
}

# ---------- 중앙 로그 (E12 #97, DEC "중앙 로그는 ELK, Loki는 비교군") ----------
# 관제 VPC에 Elasticsearch·Kibana 단일 노드. 관제 서버와 다른 AZ(2c) 서브넷에 둔다
module "logging" {
  source = "../modules/logging"

  name_prefix = "${local.name_prefix}-mon"
  region      = var.region
  vpc_id      = module.network_monitoring.vpc_id
  subnet_id   = module.network_monitoring.private_subnet_ids[1]

  peering_dependency_ids        = module.peering_monitoring_prod.route_ids
  network_egress_dependency_ids = module.network_monitoring.private_egress_dependency_ids
  log_source_security_group_id  = module.network.app_security_group_id # FireLens는 앱 태스크 ENI를 쓴다(#98)
}
