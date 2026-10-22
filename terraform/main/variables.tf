# main 루트 모듈의 입력. 환경에 따라 달라질 값은 전부 여기로 뺀다.
# 환경이 늘어나면 terraform/envs/<env>/로 옮기고 tfvars만 바꾸는 구조.

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

variable "image_tag" {
  description = "배포할 이미지 태그(커밋 SHA). 수동 배포는 tfvars, CI는 -var로 넘긴다"
  type        = string
}
