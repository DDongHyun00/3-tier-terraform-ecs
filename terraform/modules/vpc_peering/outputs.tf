output "peering_connection_id" {
  value = aws_vpc_peering_connection.this.id
}

output "route_ids" {
  description = "양쪽 경로 전부. 피어링을 건너는 SG 참조 규칙이 이것에 의존해 경로가 생긴 뒤 만들어지게 한다"
  value       = concat(aws_route.requester[*].id, aws_route.accepter[*].id)
}
