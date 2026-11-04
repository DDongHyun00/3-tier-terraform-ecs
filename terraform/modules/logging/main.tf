# 중앙 로그(E12 #97). ELK 서버의 SG와 로그 수신 규칙. 서버는 server.tf.
# 관제 VPC 안 Prometheus·Grafana 서버와 같은 방식: 공인 입구 없음, 접속은 SSM 포트 포워딩(Kibana 5601), 아웃바운드는 NAT 경유 HTTPS.

# 피어링된 VPC의 SG를 참조하는 규칙은 피어링이 active여야 만들어진다
resource "terraform_data" "peering_ready" {
  input = var.peering_dependency_ids
}

resource "aws_security_group" "elk" {
  name        = "${var.name_prefix}-sg-elk"
  description = "Elasticsearch/Kibana server: 9200 from app instances only, HTTPS out"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-sg-elk" }
}

# 운영 컨테이너 인스턴스의 Fluent Bit(host 모드)가 피어링으로 로그를 보낸다(#98)
resource "aws_vpc_security_group_ingress_rule" "es_from_app_instances" {
  security_group_id            = aws_security_group.elk.id
  description                  = "Elasticsearch HTTP from Fluent Bit on app instances"
  referenced_security_group_id = var.log_source_security_group_id
  from_port                    = 9200
  to_port                      = 9200
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

# 이미지 풀(docker.elastic.co), dnf 저장소, SSM·Secrets Manager. 모두 HTTPS, NAT 경유
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.elk.id
  description       = "HTTPS via NAT (images, packages, AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
