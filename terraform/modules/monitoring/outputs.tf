output "prometheus_security_group_id" {
  value = aws_security_group.prometheus.id
}

output "server_instance_id" {
  description = "관제 서버. SSM 포트 포워딩 대상(--target)"
  value       = aws_instance.server.id
}

output "grafana_admin_secret_name" {
  description = "Grafana admin 비밀번호가 든 Secrets Manager 비밀"
  value       = aws_secretsmanager_secret.grafana_admin.name
}
