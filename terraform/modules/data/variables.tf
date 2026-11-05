# data 모듈: RDS PostgreSQL + Secrets Manager (#25), S3·CloudFront (#26).

variable "name_prefix" {
  description = "리소스 이름 접두사. 예: 3tier-prod"
  type        = string
}

variable "db_subnet_ids" {
  description = "DB 서브넷 ID 2개 (network 모듈 출력). RDS 서브넷 그룹은 AZ 2곳을 요구한다"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "sg-db. 인바운드는 sg-app에서 5432만"
  type        = string
}

variable "db_name" {
  description = "초기 데이터베이스 이름. 앱의 DB_URL 끝에 붙는다"
  type        = string
  default     = "board"
}

variable "db_username" {
  description = "마스터 사용자 이름. 비밀번호는 random_password로 만들어 Secrets Manager에 둔다"
  type        = string
  default     = "board"
}

variable "engine_version" {
  description = "PostgreSQL 메이저 버전. 마이너는 auto_minor_version_upgrade로 자동 반영"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "DB 인스턴스 클래스. Graviton t4g가 같은 급 x86보다 싸다"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "스토리지 GB (gp3 최소 20)"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Multi-AZ. 평소 false, 장애 재현 때만 true (DEC-7)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "자동 백업 보존 일수. 반복 destroy 전제라 1일. 운영이면 7 이상"
  type        = number
  default     = 1
}

variable "account_suffix" {
  description = "AWS 계정 ID 뒤 4자리. S3 버킷 이름을 전역에서 유일하게 만드는 접미사"
  type        = string
}

variable "assets_bucket_prefix" {
  description = "첨부파일 버킷 이름 앞부분(<접두사>-<계정 접미사>). 운영 3tier-assets, 스테이징 3tier-staging-assets(배포 역할 정책 deploy_envs와 같은 이름)"
  type        = string
  default     = "3tier-assets"
}
