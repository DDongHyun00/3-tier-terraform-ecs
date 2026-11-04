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
