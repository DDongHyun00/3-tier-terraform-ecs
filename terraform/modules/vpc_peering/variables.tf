variable "name" {
  description = "피어링 연결 Name 태그. 예: 3tier-prod-pcx-mon-prod"
  type        = string
}

variable "requester_vpc_id" {
  description = "요청 쪽 VPC(관제)"
  type        = string
}

variable "requester_cidr" {
  description = "요청 쪽 VPC CIDR"
  type        = string
}

variable "requester_route_table_ids" {
  description = "요청 쪽에서 상대 CIDR 경로를 넣을 라우트 테이블"
  type        = list(string)
}

variable "accepter_vpc_id" {
  description = "수락 쪽 VPC(운영·스테이징)"
  type        = string
}

variable "accepter_cidr" {
  description = "수락 쪽 VPC CIDR"
  type        = string
}

variable "accepter_route_table_ids" {
  description = "수락 쪽에서 상대 CIDR 경로를 넣을 라우트 테이블"
  type        = list(string)
}
