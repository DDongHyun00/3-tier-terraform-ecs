# 앱 태스크 지표 탐색용 Cloud Map(E11 #94, DEC-55).
# awsvpc 태스크는 IP가 매번 바뀌어, ECS가 태스크를 비공개 DNS(A 레코드)에 등록·해제하게 하고
# 관제 VPC의 Prometheus가 그 이름을 dns_sd_configs로 조회한다. 관제 VPC 연결은 monitoring 모듈이 한다.

resource "aws_service_discovery_private_dns_namespace" "app" {
  name        = "${var.name_prefix}.internal"
  description = "Private DNS for app task discovery (Prometheus scrape)"
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "app" {
  name = "board"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.app.id
    routing_policy = "MULTIVALUE"

    # A 레코드: 태스크 IP만. 포트는 Prometheus 설정에 고정(8080)
    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  # destroy 때 등록이 남아 있어도 서비스를 지운다
  force_destroy = true
}
