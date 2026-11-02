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
