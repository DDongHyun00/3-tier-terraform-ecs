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

output "asg_names" {
  description = "컨테이너 인스턴스 ASG 이름 전부(온디맨드 + Spot, #46). 관제가 이 태그로 수집 대상을 찾는다"
  value       = concat([aws_autoscaling_group.ecs.name], aws_autoscaling_group.spot[*].name)
}

output "capacity_provider_name" {
  description = "ECS 용량 공급자 이름"
  value       = aws_ecs_capacity_provider.ec2.name
}

output "instance_security_group_id" {
  description = "컨테이너 인스턴스 SG. 관제 VPC의 Prometheus가 node_exporter·cAdvisor 포트로 들어온다(#91)"
  value       = aws_security_group.ecs_instance.id
}

output "app_discovery_dns_name" {
  description = "앱 태스크 A 레코드 이름(Cloud Map). Prometheus dns_sd_configs 대상"
  value       = "${aws_service_discovery_service.app.name}.${aws_service_discovery_private_dns_namespace.app.name}"
}

output "app_discovery_zone_id" {
  description = "Cloud Map 네임스페이스의 비공개 호스팅 존. 관제 VPC를 연결해 이름을 풀게 한다"
  value       = aws_service_discovery_private_dns_namespace.app.hosted_zone
}
