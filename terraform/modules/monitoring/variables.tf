variable "name_prefix" {
  description = "관제 리소스 이름 접두사. 3tier-prod-mon(배포 역할 권한 범위 3tier-prod-* 안)"
  type        = string
}

variable "vpc_id" {
  description = "관제 VPC"
  type        = string
}

variable "target_instance_security_group_id" {
  description = "수집 대상 ECS 컨테이너 인스턴스 SG(운영). node_exporter·cAdvisor 포트를 연다"
  type        = string
}

variable "target_app_security_group_id" {
  description = "수집 대상 앱 태스크 SG(운영). 앱 지표 포트를 연다"
  type        = string
}

variable "peering_dependency_ids" {
  description = "피어링 경로 ID. 값은 쓰지 않고 SG 참조 규칙이 피어링 뒤에 만들어지게 하는 데만 쓴다"
  type        = list(string)
}

variable "node_exporter_port" {
  description = "node_exporter 호스트 포트(host 모드, DEC-56)"
  type        = number
  default     = 9100
}

variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트(bridge 모드 8081 → 컨테이너 8080, DEC-56)"
  type        = number
  default     = 8081
}

variable "app_metrics_port" {
  description = "앱 컨테이너 포트(/actuator/prometheus, #94)"
  type        = number
  default     = 8080
}

# ---------- 관제 서버 (#92) ----------
variable "region" {
  description = "ec2_sd_configs·Secrets Manager 호출 리전"
  type        = string
}

variable "subnet_id" {
  description = "관제 서버를 둘 관제 VPC 사설 서브넷(2a)"
  type        = string
}

variable "target_asg_name" {
  description = "수집 대상 ECS 컨테이너 인스턴스 ASG 이름. 인스턴스에 자동으로 붙는 aws:autoscaling:groupName 태그로 찾는다"
  type        = string
}

variable "instance_type" {
  description = "관제 서버 인스턴스 유형(DEC-54: t4g.small, 2 GiB, arm64)"
  type        = string
  default     = "t4g.small"
}

variable "root_volume_size" {
  description = "루트 볼륨(GB, gp3, 암호화). OS·이미지·세션 동안의 지표(DEC-59)"
  type        = number
  default     = 20
}

variable "scrape_interval" {
  description = "수집 간격. CloudWatch 1분·4분 지연과 비교하려고 15초(DEC-39)"
  type        = string
  default     = "15s"
}

variable "retention" {
  description = "Prometheus 보존 기간 설정. 서버가 세션마다 지워져 실제로는 세션 동안만 남는다(DEC-59)"
  type        = string
  default     = "15d"
}

# 이미지·도구 버전은 고정한다(재현성). 공식 이미지는 모두 arm64를 낸다
variable "prometheus_image" {
  type    = string
  default = "prom/prometheus:v2.53.0"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:11.1.0"
}

variable "node_exporter_image" {
  type    = string
  default = "prom/node-exporter:v1.8.1"
}

variable "compose_version" {
  description = "docker compose 플러그인 릴리스(AL2023 저장소에 없어 GitHub 릴리스에서 받는다)"
  type        = string
  default     = "v2.27.0"
}

variable "network_egress_dependency_ids" {
  description = "관제 VPC 사설 서브넷의 인터넷 경로 리소스 ID(network 모듈 private_egress_dependency_ids). 값은 쓰지 않고 서버가 경로 뒤에 만들어지고 앞에 지워지게 하는 데만 쓴다"
  type        = list(string)
}

variable "app_discovery_zone_id" {
  description = "앱 Cloud Map 네임스페이스의 비공개 호스팅 존 ID(compute 출력)"
  type        = string
}

variable "app_discovery_dns_name" {
  description = "앱 태스크 A 레코드 이름(compute 출력). 예: board.3tier-prod.internal"
  type        = string
}

# ---------- Grafana 대시보드·알림 (#95, DEC-58) ----------
variable "alarm_topic_arn" {
  description = "기존 알람 SNS 토픽(bootstrap). Grafana 알림도 여기로 보내 Q Developer → Slack 경로를 같이 쓴다"
  type        = string
}

variable "app_cpu_reservation" {
  description = "앱 태스크 CPU 예약(vCPU). 컨테이너 CPU %를 CloudWatch ECS CPUUtilization과 같은 기준(예약 대비)으로 계산한다"
  type        = number
  default     = 0.5
}

variable "cpu_warning_percent" {
  description = "앱 CPU 경고 기준(3분 지속)"
  type        = number
  default     = 60
}

variable "cpu_critical_percent" {
  description = "앱 CPU 심각 기준(3분 지속)"
  type        = number
  default     = 80
}

# ---------- RDS 알림 (CloudWatch 데이터 소스, DEC-45·62) ----------
# CloudWatch 알람에서 옮겨 온 기준이다. RDS 지표는 CloudWatch에만 있어 Grafana CloudWatch 데이터 소스로 읽는다
variable "db_identifier" {
  description = "RDS 식별자. CloudWatch 지표 차원 DBInstanceIdentifier 값"
  type        = string
}

variable "rds_storage_low_bytes" {
  description = "RDS 여유 스토리지 알림 기준(바이트). 2 GB"
  type        = number
  default     = 2147483648
}

variable "rds_connections_high" {
  description = "RDS 연결 수 알림 기준(3분 지속). db.t4g.micro 기본 max_connections(약 80 추정)의 75%. HikariCP 풀 10 × 태스크 수"
  type        = number
  default     = 60
}
