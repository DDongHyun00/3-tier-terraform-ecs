# network 모듈이 받는 값. 숫자는 docs/architecture.md 5절에서 온다.

variable "name_prefix" {
  description = "리소스 이름 접두사. 예: 3tier-prod"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "사용할 가용 영역. 서브넷 CIDR 목록과 순서가 같아야 한다"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 (ALB, NAT). AZ 순서대로"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 (ECS 태스크). AZ 순서대로"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_subnet_cidrs" {
  description = "DB 서브넷 (RDS). AZ 순서대로"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "app_port" {
  description = "앱 컨테이너 포트. ALB → 앱"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "DB 포트. 앱 → DB"
  type        = number
  default     = 5432
}

variable "az_suffixes" {
  description = "서브넷 이름에 붙일 AZ 약자. azs와 순서가 같다"
  type        = list(string)
  default     = ["a", "c"]
}
