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

variable "slack_team_id" {
  description = "Q Developer에 인증한 Slack 워크스페이스 ID(T로 시작). Q Developer 콘솔의 클라이언트 화면에서 확인"
  type        = string
}

variable "slack_channel_id" {
  description = "알람을 받을 Slack 채널 ID(C로 시작, #aws-alerts). Slack 채널 정보 맨 아래에서 확인"
  type        = string
}

variable "github_owner_id" {
  description = "GitHub 계정의 숫자 ID. OIDC sub 클레임의 불변 식별자. gh api users/<owner> --jq .id"
  type        = number
  default     = 117076978
}

variable "github_repo_id" {
  description = "GitHub 레포의 숫자 ID. OIDC sub 클레임의 불변 식별자. gh api repos/<owner>/<name> --jq .id"
  type        = number
  default     = 1407473189
}
