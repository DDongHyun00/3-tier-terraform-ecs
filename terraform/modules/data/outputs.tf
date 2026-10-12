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
