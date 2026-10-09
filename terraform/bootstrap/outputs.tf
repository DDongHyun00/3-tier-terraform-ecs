# main 루트 모듈이 가져다 쓰는 값들.
# main은 이 값을 terraform_remote_state 또는 변수로 받는다.

output "tfstate_bucket" {
  description = "Terraform state 버킷 이름. main의 backend 설정에 쓴다"
  value       = aws_s3_bucket.tfstate.id
}

output "github_deploy_role_arn" {
  description = "GitHub Actions가 수임할 배포 역할 ARN. 워크플로의 role-to-assume에 쓴다"
  value       = aws_iam_role.github_deploy.arn
}

output "ecr_repository_url" {
  description = "ECR 리포지토리 URL. 이미지 push와 ECS 태스크 정의에 쓴다"
  value       = aws_ecr_repository.board.repository_url
}

output "hosted_zone_id" {
  description = "Route 53 호스팅 존 ID. ACM DNS 검증과 A 레코드 생성에 쓴다"
  value       = data.aws_route53_zone.main.zone_id
}
