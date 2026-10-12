output "db_endpoint" {
  description = "RDS 엔드포인트 호스트. 앱의 DB_URL에 쓴다"
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_secret_arn" {
  description = "Secrets Manager 시크릿 ARN. ECS 태스크 실행 역할이 읽는다"
  value       = aws_secretsmanager_secret.db.arn
}

output "assets_bucket_name" {
  description = "첨부파일·정적 파일 버킷. 앱의 S3_BUCKET 환경 변수"
  value       = aws_s3_bucket.assets.id
}

output "assets_bucket_arn" {
  value = aws_s3_bucket.assets.arn
}

output "cloudfront_domain_name" {
  description = "정적 파일 서빙 도메인 (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.assets.domain_name
}

output "assets_rw_policy_arn" {
  description = "태스크 역할에 붙일 S3 읽기·쓰기 정책"
  value       = aws_iam_policy.assets_rw.arn
}
