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
