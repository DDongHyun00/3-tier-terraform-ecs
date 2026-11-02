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

# CloudWatch 지표의 LoadBalancer·TargetGroup 차원 값. ARN 뒤쪽(app/<이름>/<id>, targetgroup/<이름>/<id>)이다
output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "asg_name" {
  description = "컨테이너 인스턴스 ASG 이름(#89 인스턴스 스케일링 측정)"
  value       = aws_autoscaling_group.ecs.name
}

output "capacity_provider_name" {
  description = "ECS 용량 공급자 이름"
  value       = aws_ecs_capacity_provider.ec2.name
}
