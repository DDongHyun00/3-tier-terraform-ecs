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

# ---------- 오토스케일링 (#39, docs/architecture.md 6.1절) ----------
variable "autoscaling_min" {
  description = "최소 태스크 수. AZ마다 1개"
  type        = number
  default     = 2
}

variable "autoscaling_max" {
  description = "최대 태스크 수"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "목표 추적 기준. 서비스 평균 CPU를 이 값(%) 근처로 유지하도록 태스크 수를 바꾼다"
  type        = number
  default     = 60
}

variable "scale_out_cooldown" {
  description = "늘린 뒤 다음 늘림까지 기다리는 초. 새 태스크 기동(약 23초)과 헬스체크 2회(30초)를 지나면 다시 판단"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "줄인 뒤 다음 줄임까지 기다리는 초. Application Auto Scaling의 ECS 기본값. 부하가 출렁일 때 늘렸다 줄였다 반복하는 것을 막는다"
  type        = number
  default     = 300
}
