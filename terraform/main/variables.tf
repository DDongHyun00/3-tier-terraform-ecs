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
