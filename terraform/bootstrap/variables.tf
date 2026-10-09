variable "account_suffix" {
  description = "AWS 계정 ID 뒤 4자리. S3 버킷 이름을 전역에서 유일하게 만드는 접미사"
  type        = string
}

variable "github_repo" {
  description = "GitHub 레포 (owner/name). OIDC 배포 역할이 이 레포에서만 수임되도록 제한"
  type        = string
}

variable "domain_name" {
  description = "Route 53 호스팅 존 이름"
  type        = string
}