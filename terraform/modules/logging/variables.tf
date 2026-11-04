# logging 모듈: 관제 VPC의 Elasticsearch·Kibana 단일 노드(E12 #97). 로그 수집기(Fluent Bit)는 #98.

variable "name_prefix" {
  description = "리소스 이름 접두사. 관제 VPC와 같은 3tier-prod-mon(배포 역할 권한 범위 3tier-prod-* 안)"
  type        = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  description = "관제 VPC"
  type        = string
}

variable "subnet_id" {
  description = "ELK 서버를 둘 관제 VPC 사설 서브넷"
  type        = string
}

variable "peering_dependency_ids" {
  description = "관제 ↔ 운영 피어링 경로 ID. 운영 SG를 참조하는 규칙을 피어링 active 뒤에 만들려고 쓴다"
  type        = list(string)
}

variable "network_egress_dependency_ids" {
  description = "관제 VPC 사설 서브넷의 인터넷 경로 리소스 ID. 서버가 경로 뒤에 만들어지고 앞에 지워지게 하는 데만 쓴다"
  type        = list(string)
}

variable "log_source_security_group_id" {
  description = "로그를 보내는 쪽 SG(운영 ECS 컨테이너 인스턴스). Fluent Bit가 host 모드라 인스턴스 SG에서 9200으로 들어온다"
  type        = string
}

variable "instance_type" {
  description = "ELK 서버. Elasticsearch 힙 1 GB + Kibana 약 1 GB + OS 여유로 4 GiB(t4g.medium). ARM이라 같은 크기 x86보다 싸다"
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "루트 볼륨(GB). OS·이미지(약 3 GB)와 세션 동안의 로그 인덱스"
  type        = number
  default     = 30
}

variable "es_heap" {
  description = "Elasticsearch JVM 힙(-Xms·-Xmx 같은 값). 메모리의 절반 이하가 권장이고 Kibana와 나눠 쓴다"
  type        = string
  default     = "1g"
}

variable "log_index_prefix" {
  description = "앱 로그 인덱스 접두사. logs-*-*는 Elasticsearch 기본 데이터 스트림 템플릿과 겹쳐 피했다"
  type        = string
  default     = "app-board"
}

# 이미지·도구 버전은 고정한다(재현성). Elastic 공식 이미지는 arm64를 낸다
variable "elasticsearch_image" {
  type    = string
  default = "docker.elastic.co/elasticsearch/elasticsearch:9.5.5"
}

variable "kibana_image" {
  type    = string
  default = "docker.elastic.co/kibana/kibana:9.5.5"
}

variable "compose_version" {
  type    = string
  default = "v2.27.0"
}
