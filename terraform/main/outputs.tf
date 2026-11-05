output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}

output "security_group_ids" {
  value = {
    alb = module.network.alb_security_group_id
    app = module.network.app_security_group_id
    db  = module.network.db_security_group_id
  }
}

output "db_endpoint" {
  value = module.data.db_endpoint
}

output "db_secret_arn" {
  value = module.data.db_secret_arn
}

output "assets_bucket_name" {
  value = module.data.assets_bucket_name
}

output "cloudfront_domain_name" {
  value = module.data.cloudfront_domain_name
}

output "site_url" {
  value = module.compute.site_url
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.compute.cluster_name
}

output "ecs_service_name" {
  value = module.compute.service_name
}

output "log_group_name" {
  value = module.compute.log_group_name
}

output "monitoring_vpc_id" {
  description = "관제 VPC(E11)"
  value       = try(module.network_monitoring[0].vpc_id, null)
}

output "peering_monitoring_prod_id" {
  description = "관제 ↔ 운영 VPC 피어링"
  value       = try(module.peering_monitoring_prod[0].peering_connection_id, null)
}

output "nat_gateway_ids" {
  description = "운영 리전 NAT, 관제 영역 NAT"
  value = {
    prod       = module.network.nat_gateway_id
    monitoring = try(module.network_monitoring[0].nat_gateway_id, null)
  }
}

output "monitoring_server_instance_id" {
  description = "관제 서버. aws ssm start-session --target <이 값> --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000"
  value       = try(module.monitoring[0].server_instance_id, null)
}

output "grafana_admin_secret_name" {
  value = try(module.monitoring[0].grafana_admin_secret_name, null)
}

output "elk_instance_id" {
  description = "ELK 서버(E12). Kibana: aws ssm start-session --target <이 값> --document-name AWS-StartPortForwardingSession --parameters portNumber=5601,localPortNumber=5601"
  value       = try(module.logging[0].elk_instance_id, null)
}

output "elastic_secret_name" {
  description = "Kibana 로그인 사용자 elastic의 비밀번호가 든 비밀"
  value       = try(module.logging[0].elastic_secret_name, null)
}
