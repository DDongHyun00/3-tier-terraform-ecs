# compute 모듈: ECS Fargate + ALB + ACM + Route 53 (#27). 설계: docs/architecture.md 6.1절, 7.2절.

variable "name_prefix" {
  description = "리소스 이름 접두사. 예: 3tier-prod"
  type        = string
}

variable "region" {
  description = "AWS 리전. 로그 설정과 앱의 AWS_REGION 환경 변수에 쓴다"
  type        = string
}

# ---------- 네트워크 (network 모듈 출력) ----------
variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "ALB가 들어갈 퍼블릭 서브넷 2개"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "ECS 태스크가 들어갈 프라이빗 서브넷 2개"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "sg-alb. 인바운드 80·443"
  type        = string
}

variable "app_security_group_id" {
  description = "sg-app. 인바운드는 sg-alb에서 app_port만"
  type        = string
}

# ---------- 앱 ----------
variable "image" {
  description = "컨테이너 이미지. <ECR URL>:<태그>. 태그는 커밋 SHA"
  type        = string
}

variable "app_port" {
  description = "컨테이너가 듣는 포트. Dockerfile EXPOSE와 같아야 한다"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "태스크 CPU 단위. 512 = 0.5 vCPU. 256(0.25)은 기동 120초, 첫 응답 수 초라 올렸다 (DEC, E05)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "태스크 메모리 MB. 0.5 vCPU에 허용되는 값은 1024~4096"
  type        = number
  default     = 1024
}

variable "java_tool_options" {
  description = "JVM 옵션. 컨테이너 ENV를 덮어쓴다. TieredStopAtLevel=1은 기동·첫 요청을 빠르게 한다(최고 처리량은 조금 손해)"
  type        = string
  default     = "-XX:MaxRAMPercentage=75.0 -XX:TieredStopAtLevel=1"
}

variable "desired_count" {
  description = "원하는 태스크 수. AZ마다 1개"
  type        = number
  default     = 2
}

variable "health_check_path" {
  description = "ALB 헬스체크 경로. DB 상태와 무관한 liveness를 본다"
  type        = string
  default     = "/actuator/health/liveness"
}

variable "health_check_grace_period" {
  description = "서비스 시작 후 ALB 헬스체크 실패를 무시하는 초. 앱 기동 시간(0.25 vCPU 약 120초)의 2배"
  type        = number
  default     = 240
}

variable "log_retention_days" {
  description = "CloudWatch Logs 보존 일수"
  type        = number
  default     = 7
}

variable "stop_timeout" {
  description = "SIGTERM 후 강제 종료까지 초. 앱의 graceful 유예(20초)보다 길게"
  type        = number
  default     = 30
}

# ---------- 데이터 계층 (data 모듈 출력) ----------
variable "db_url" {
  description = "JDBC URL. jdbc:postgresql://<엔드포인트>:5432/board"
  type        = string
}

variable "db_secret_arn" {
  description = "DB 자격 증명 시크릿 ARN. 실행 역할이 username·password 키를 읽어 주입한다"
  type        = string
}

variable "assets_bucket_name" {
  description = "첨부파일 버킷. 앱의 S3_BUCKET 환경 변수"
  type        = string
}

variable "assets_rw_policy_arn" {
  description = "태스크 역할에 붙일 S3 읽기·쓰기 정책"
  type        = string
}

# ---------- 도메인 ----------
variable "domain_name" {
  description = "서비스 도메인. ACM 인증서와 A 레코드에 쓴다"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 호스팅 존 ID"
  type        = string
}
