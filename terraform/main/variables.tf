# main 루트 모듈의 입력. 환경에 따라 달라질 값은 전부 여기로 뺀다.
# 스테이징은 별도 루트(terraform/staging)가 같은 모듈을 작은 값으로 호출한다.

variable "env" {
  description = "환경 이름. 리소스 이름(3tier-<env>-*)과 태그 Env에 쓴다"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "가용 영역 2곳"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "multi_az" {
  description = "RDS Multi-AZ. 평소 false, 장애 재현 때만 true"
  type        = bool
  default     = false
}

variable "account_suffix" {
  description = "AWS 계정 ID 뒤 4자리. S3 버킷 이름 접미사 (tfvars)"
  type        = string
}

variable "domain_name" {
  description = "서비스 도메인. Route 53 호스팅 존 이름이자 ACM 인증서 도메인"
  type        = string
  default     = "3tier.link"
}

# ---------- 비용 스위치 (E09 #46, DEC-67) ----------
# 운영 기본값은 켜짐. 운영 관측은 끄지 않는다(Well-Architected COST09는 비운영 리소스를 끄라고 한다).
# 짧은 확인 세션처럼 일부러 끌 때만 false. 관제+로그가 시간당 비용의 약 34%(docs/cost.md 6·7절)
variable "enable_monitoring" {
  description = "관제 VPC의 Prometheus·Grafana와 수집 에이전트"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "관제 VPC의 ELK와 앱 FireLens. 끄면 앱 로그는 CloudWatch Logs(awslogs)로 간다"
  type        = bool
  default     = true
}

variable "enable_spot" {
  description = "앱 컨테이너 인스턴스에 Spot 용량 공급자를 더한다(온디맨드 base 1 + 나머지 Spot)"
  type        = bool
  default     = true
}
