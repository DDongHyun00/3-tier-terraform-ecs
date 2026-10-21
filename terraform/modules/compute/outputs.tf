output "alb_dns_name" {
  description = "ALB DNS 이름. 도메인 전파 전 직접 접속 확인용"
  value       = aws_lb.this.dns_name
}

output "site_url" {
  value = "https://${var.domain_name}"
}

output "cluster_name" {
  description = "describe-services, update-service에 쓴다"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
