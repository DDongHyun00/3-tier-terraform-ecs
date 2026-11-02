# 다른 모듈(data, compute)이 가져다 쓰는 값.

output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "ALB가 들어갈 서브넷"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "ECS 태스크가 들어갈 서브넷"
  value       = aws_subnet.private[*].id
}

output "db_subnet_ids" {
  description = "RDS 서브넷 그룹에 넣을 서브넷"
  value       = aws_subnet.db[*].id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "private_egress_dependency_ids" {
  description = "사설 서브넷에서 인터넷으로 나가는 경로를 이루는 리소스 전부: 사설 기본 경로(→ NAT), 사설 라우트 테이블 연결, 퍼블릭 기본 경로(→ IGW), 퍼블릭 라우트 테이블 연결. 사설 서브넷에서 밖으로 나가는 리소스(ECS 서비스·ASG)가 이 목록에 의존하게 해, destroy 때 경로의 어느 조각도 그 리소스들보다 먼저 지워지지 않게 한다. 경로 중 하나만 빠져도 ECS agent 통신이 끊긴다"
  value = concat(
    aws_route.private_nat[*].id,
    aws_route_table_association.private[*].id,
    [aws_route.public_internet.id],
    aws_route_table_association.public[*].id,
  )
}
