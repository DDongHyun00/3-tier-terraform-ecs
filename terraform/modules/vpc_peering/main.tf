# VPC 피어링 하나와 양쪽 사설 라우트 테이블의 경로(E11 #91, DEC-40).
# 같은 계정·리전이라 요청과 동시에 수락(auto_accept)한다. 피어링은 전이 라우팅을 하지 않으므로
# 관제↔운영, 관제↔스테이징을 따로 만들면 운영↔스테이징은 자동으로 막힌다.

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true

  tags = { Name = var.name }
}

# 요청 쪽(관제) 사설 라우트 테이블 → 수락 쪽 CIDR
resource "aws_route" "requester" {
  count                     = length(var.requester_route_table_ids)
  route_table_id            = var.requester_route_table_ids[count.index]
  destination_cidr_block    = var.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# 수락 쪽(운영) 사설 라우트 테이블 → 요청 쪽 CIDR. DB 라우트 테이블에는 넣지 않는다(관제가 DB에 갈 일이 없다)
resource "aws_route" "accepter" {
  count                     = length(var.accepter_route_table_ids)
  route_table_id            = var.accepter_route_table_ids[count.index]
  destination_cidr_block    = var.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
