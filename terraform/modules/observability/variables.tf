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
