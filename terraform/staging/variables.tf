variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "azs" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "account_suffix" {
  description = "S3 버킷 이름 접미사(계정 ID 끝 4자리). terraform.tfvars 또는 TF_VAR_account_suffix"
  type        = string
}

variable "domain_name" {
  description = "운영 공개 존. 스테이징은 그 아래 staging.<존> 레코드를 쓴다"
  type        = string
  default     = "3tier.link"
}

variable "image_tag" {
  description = "배포할 이미지 태그(커밋 SHA 앞 7자리). 비우면 ECR 최신 이미지. 승인 배포(#102)는 운영과 같은 태그를 넘긴다"
  type        = string
  default     = ""
}
