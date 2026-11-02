# 관제(Prometheus·Grafana). 이 파일은 SG와 수집 포트 규칙(#91), 서버는 server.tf(#92).
# 설계: E11 설계 4·5절, DEC-55·56.

# 피어링 경로가 생긴 뒤에 SG 참조 규칙을 만든다. 피어링된 VPC의 SG를 참조하는 규칙은 피어링이 active여야 만들어진다.
resource "terraform_data" "peering_ready" {
  input = var.peering_dependency_ids
}

resource "aws_security_group" "prometheus" {
  name        = "${var.name_prefix}-sg-prometheus"
  description = "Prometheus/Grafana server: no ingress, scrape app VPC, HTTPS out"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-sg-prometheus" }
}

# ---------- Prometheus 아웃바운드 ----------
# 수집 대상은 SG 참조로 좁힌다(인스턴스·태스크 IP는 바뀌어도 SG는 그대로)
resource "aws_vpc_security_group_egress_rule" "to_node_exporter" {
  security_group_id            = aws_security_group.prometheus.id
  description                  = "Scrape node_exporter on app instances"
  referenced_security_group_id = var.target_instance_security_group_id
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

resource "aws_vpc_security_group_egress_rule" "to_cadvisor" {
  security_group_id            = aws_security_group.prometheus.id
  description                  = "Scrape cAdvisor on app instances"
  referenced_security_group_id = var.target_instance_security_group_id
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

resource "aws_vpc_security_group_egress_rule" "to_app_metrics" {
  security_group_id            = aws_security_group.prometheus.id
  description                  = "Scrape app /actuator/prometheus"
  referenced_security_group_id = var.target_app_security_group_id
  from_port                    = var.app_metrics_port
  to_port                      = var.app_metrics_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

# 이미지 풀(Docker Hub·GitHub), dnf 저장소, SSM·Secrets Manager·EC2 API. 모두 HTTPS, NAT 경유
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.prometheus.id
  description       = "HTTPS via NAT (images, packages, AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ---------- 수집 대상 쪽 인바운드 ----------
resource "aws_vpc_security_group_ingress_rule" "instance_node_exporter" {
  security_group_id            = var.target_instance_security_group_id
  description                  = "node_exporter from Prometheus (monitoring VPC)"
  referenced_security_group_id = aws_security_group.prometheus.id
  from_port                    = var.node_exporter_port
  to_port                      = var.node_exporter_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

resource "aws_vpc_security_group_ingress_rule" "instance_cadvisor" {
  security_group_id            = var.target_instance_security_group_id
  description                  = "cAdvisor from Prometheus (monitoring VPC)"
  referenced_security_group_id = aws_security_group.prometheus.id
  from_port                    = var.cadvisor_port
  to_port                      = var.cadvisor_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}

resource "aws_vpc_security_group_ingress_rule" "app_metrics" {
  security_group_id            = var.target_app_security_group_id
  description                  = "App metrics from Prometheus (monitoring VPC)"
  referenced_security_group_id = aws_security_group.prometheus.id
  from_port                    = var.app_metrics_port
  to_port                      = var.app_metrics_port
  ip_protocol                  = "tcp"

  depends_on = [terraform_data.peering_ready]
}
