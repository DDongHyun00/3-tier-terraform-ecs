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

# ---------- ECS on EC2 (#87, DEC-50) ----------
variable "instance_type" {
  description = "컨테이너 인스턴스 타입. t3.small은 1 GB 앱 태스크가 1개만 들어가 태스크 수만큼 인스턴스가 늘어난다"
  type        = string
  default     = "t3.small"
}

variable "asg_min_size" {
  description = "ASG 최소 인스턴스 수. 서비스 태스크 하한(2)과 맞춘다"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "ASG 최대 인스턴스 수. 서비스 태스크 상한(4)의 2배. 인스턴스당 태스크 1개라 롤링 배포(최소 100%·최대 200%)가 태스크 4개 상태에서도 새 태스크를 놓을 자리가 있어야 한다. 상한일 뿐 평시 대수는 용량 공급자가 정한다"
  type        = number
  default     = 8
}

variable "root_volume_size" {
  description = "인스턴스 루트 볼륨(GB, gp3, 암호화)"
  type        = number
  default     = 30
}

variable "network_egress_dependency_ids" {
  description = "사설 서브넷의 인터넷 경로를 이루는 리소스 ID 목록(사설 기본 경로·라우트 테이블 연결·퍼블릭 기본 경로·퍼블릭 연결). 값 자체는 쓰지 않고 의존 관계에만 쓴다. destroy 때 NAT가 먼저 지워지면 사설 서브넷 인스턴스의 ECS agent가 태스크 정지를 보고하지 못해 서비스가 DRAINING에 고착된다(11/02, #108)"
  type        = list(string)
  default     = []
}

# ---------- 지표 에이전트 (E11 #93, DEC-56) ----------
variable "enable_metrics_agents" {
  description = "node_exporter·cAdvisor 데몬 서비스를 띄울지. 관제(Prometheus)가 없는 환경(스테이징 등)은 false"
  type        = bool
  default     = true
}

variable "node_exporter_port" {
  description = "node_exporter 호스트 포트(host 모드). 관제 SG 규칙(monitoring 모듈)과 같아야 한다"
  type        = number
  default     = 9100
}

variable "cadvisor_port" {
  description = "cAdvisor 호스트 포트(bridge 8081 → 컨테이너 8080). 관제 SG 규칙과 같아야 한다"
  type        = number
  default     = 8081
}

# 운영 인스턴스는 x86(t3.small, DEC-50). 두 이미지 모두 amd64 빌드가 있다
variable "node_exporter_image" {
  type    = string
  default = "prom/node-exporter:v1.8.1"
}

variable "cadvisor_image" {
  type    = string
  default = "gcr.io/cadvisor/cadvisor:v0.49.1"
}

variable "permissions_boundary_name" {
  description = "이 모듈이 만드는 역할에 붙일 permissions boundary(bootstrap). 운영 3tier-ecs-boundary, 스테이징 3tier-staging-ecs-boundary(DEC-63)"
  type        = string
  default     = "3tier-ecs-boundary"
}

# ---------- 로그 라우터 (E12 #98, FireLens) ----------
# 켜면 앱 로그를 FireLens(Fluent Bit 사이드카)로 Elasticsearch에 보낸다. 끄면 지금처럼 awslogs → CloudWatch Logs
variable "enable_log_router" {
  description = "앱 로그를 FireLens로 Elasticsearch에 보낼지. 스테이징처럼 ELK가 없는 환경은 false"
  type        = bool
  default     = false
}

variable "log_router_image" {
  description = "AWS for Fluent Bit. FireLens 공식 이미지이고 JSON 파싱 설정(/fluent-bit/configs/parse-json.conf)을 포함한다"
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:2.34.3.20261028"
}

variable "elasticsearch_host" {
  description = "로그를 받을 Elasticsearch 사설 IP(관제 VPC, 피어링 경유)"
  type        = string
  default     = ""
}

variable "elasticsearch_user_secret_arn" {
  description = "Fluent Bit 계정(fluentbit) 비밀번호가 든 비밀. 실행 역할이 읽어 HTTP_Passwd로 넣는다"
  type        = string
  default     = ""
}

variable "log_index_prefix" {
  description = "앱 로그 인덱스 접두사(logging 모듈과 같은 값). 날짜별 인덱스 <접두사>-YYYY.MM.DD"
  type        = string
  default     = "app-board"
}

# ---------- Spot (E09 #46, DEC-67) ----------
variable "enable_spot" {
  description = "Spot ASG·용량 공급자를 더해 온디맨드 base 뒤의 태스크를 Spot에 놓을지"
  type        = bool
  default     = false
}

variable "on_demand_base" {
  description = "Spot을 켰을 때 항상 온디맨드에 둘 태스크 수. Spot이 한꺼번에 회수돼도 이만큼은 남는다"
  type        = number
  default     = 1
}

variable "spot_instance_types" {
  description = "Spot ASG가 고를 인스턴스 타입. 모두 2 GiB(앱 태스크 1개/대)이고 awsvpc 태스크 1개에 필요한 네트워크 카드 2개 이상"
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
}

variable "spot_asg_max_size" {
  description = "Spot ASG 최대 인스턴스 수(태스크 상한 4 + 롤링 배포 여유)"
  type        = number
  default     = 8
}
