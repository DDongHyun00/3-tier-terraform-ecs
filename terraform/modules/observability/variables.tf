# observability 모듈: CloudWatch 대시보드 (#37). 설계: docs/architecture.md 4절, 6.1절.

variable "name_prefix" {
  description = "리소스 이름 접두사. 예: 3tier-prod"
  type        = string
}

variable "region" {
  description = "AWS 리전. 대시보드 위젯이 이 리전의 지표를 읽는다"
  type        = string
}

# ---------- ALB (compute 모듈 출력) ----------
variable "alb_arn_suffix" {
  description = "ALB ARN 뒤쪽. 지표 차원 LoadBalancer 값"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "타깃 그룹 ARN 뒤쪽. 지표 차원 TargetGroup 값"
  type        = string
}

# ---------- ECS (compute 모듈 출력) ----------
variable "cluster_name" {
  description = "ECS 클러스터 이름. 지표 차원 ClusterName 값"
  type        = string
}

variable "service_name" {
  description = "ECS 서비스 이름. 지표 차원 ServiceName 값"
  type        = string
}

# ---------- RDS (data 모듈 출력) ----------
variable "db_identifier" {
  description = "RDS 식별자(db-3tier-prod). 지표 차원 DBInstanceIdentifier 값"
  type        = string
}

# ---------- 알람 (#38) ----------
variable "alarm_topic_arn" {
  description = "알람·복구 알림을 보낼 SNS 토픽(3tier-prod-alarms, bootstrap). Q Developer가 Slack으로 넘긴다"
  type        = string
}

variable "alb_5xx_rate_percent" {
  description = "ALB 5xx 비율 알람 임계(%). 5분 중 3분 넘으면 울린다"
  type        = number
  default     = 5
}

variable "alb_5xx_min_requests" {
  description = "분당 요청이 이보다 적으면 5xx 비율을 0으로 본다. 평시 SSE 끊김 5xx 1건이 비율을 50~100%로 튀게 하는 오경보 방지"
  type        = number
  default     = 10
}

variable "ecs_cpu_high_percent" {
  description = "ECS 서비스 평균 CPU 알람 임계(%). 5분 연속이면 울린다. 오토스케일링(목표 60%)으로도 못 따라가는 상태"
  type        = number
  default     = 80
}

variable "rds_storage_low_bytes" {
  description = "RDS 여유 스토리지 알람 임계(바이트). 2 GB"
  type        = number
  default     = 2147483648
}

variable "rds_connections_high" {
  description = "RDS 연결 수 알람 임계. db.t4g.micro 기본 max_connections(약 80 추정)의 75%. HikariCP 풀 10 × 태스크 수"
  type        = number
  default     = 60
}
