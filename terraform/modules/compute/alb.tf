# ALB + 타깃 그룹 + ACM 인증서 + 리스너 + Route 53 A 레코드.

# ---------- ALB ----------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]

  # 반복 destroy 전제. 운영이면 true
  enable_deletion_protection = false
}

# Fargate(awsvpc)는 태스크마다 ENI가 있어서 타깃 유형이 instance가 아니라 ip다.
resource "aws_lb_target_group" "app" {
  name        = "${var.name_prefix}-tg"
  vpc_id      = var.vpc_id
  target_type = "ip"
  port        = var.app_port
  protocol    = "HTTP"

  # 15초 간격, 연속 2회 성공이면 healthy, 2회 실패면 unhealthy. 최악 30초 안에 빠진다
  health_check {
    path                = var.health_check_path
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  # 태스크를 뺄 때 처리 중 요청을 기다리는 시간. 기본 300초는 롤링 배포를 느리게 한다
  deregistration_delay = 30
}

# ---------- ACM (DNS 검증) ----------
# 인증서 요청, ACM이 준 CNAME을 Route 53에 생성, 발급 완료 대기. 리소스 3개가 한 세트.
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # 갱신·교체 시 새 인증서를 먼저 만들고 리스너를 옮긴 뒤 옛것을 지운다
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------- 리스너 ----------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  # validation의 certificate_arn을 쓰면 발급 완료 뒤에 리스너가 만들어진다
  certificate_arn = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ---------- Route 53 ----------
# alias 레코드: ALB의 IP가 바뀌어도 따라간다. CNAME과 달리 루트 도메인에도 쓸 수 있다.
resource "aws_route53_record" "app" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# /actuator/prometheus는 ALB로 공개하지 않는다(#94). 관제 VPC의 Prometheus는 피어링으로 태스크 8080에 직접 붙는다.
# 앱은 이 경로를 인증 없이 열어 두므로(SecurityConfig) 공개 경로에서 막는 이 규칙이 필요하다
resource "aws_lb_listener_rule" "block_metrics" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/actuator/prometheus", "/actuator/prometheus/*"]
    }
  }

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}
