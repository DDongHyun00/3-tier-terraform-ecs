output "elk_instance_id" {
  description = "ELK 서버. SSM 포트 포워딩 대상(Kibana 5601)"
  value       = aws_instance.server.id
}

output "elasticsearch_endpoint" {
  description = "Fluent Bit가 로그를 보낼 주소(관제 VPC 사설 IP, 피어링 경유)"
  value       = "${aws_instance.server.private_ip}:9200"
}

output "elk_private_ip" {
  value = aws_instance.server.private_ip
}

output "elastic_secret_name" {
  description = "Kibana 로그인(elastic) 비밀번호가 든 비밀"
  value       = aws_secretsmanager_secret.elastic.name
}

output "fluentbit_secret_arn" {
  description = "Fluent Bit 계정 비밀번호 비밀(#98 태스크 정의가 ECS secrets로 주입)"
  value       = aws_secretsmanager_secret.fluentbit.arn
}

output "log_index_prefix" {
  value = var.log_index_prefix
}

output "security_group_id" {
  value = aws_security_group.elk.id
}
