# 관제 서버: Prometheus·Grafana·node_exporter를 docker compose로 올리는 EC2 1대(E11 #92).
# 설계: E11 설계 5절, DEC-54(t4g.small ARM), DEC-55(ec2_sd_configs), DEC-57(SSM 포트 포워딩), DEC-59(세션 동안만 보관).

data "aws_caller_identity" "current" {}

locals {
  # 배포 역할은 boundary가 붙은 역할만 만들 수 있다(#35). 관제 역할의 상한도 같은 boundary에 넣었다(#111)
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/3tier-ecs-boundary"
}

# AL2023 arm64 최신 AMI(공개 SSM 파라미터). ECS 최적화 AMI가 아닌 일반 AMI다(ECS 클러스터에 붙지 않는다)
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------- Grafana 관리자 비밀번호 ----------
resource "random_password" "grafana_admin" {
  length  = 24
  special = false # 셸·.env에서 따옴표 처리 없이 쓰려고 영숫자만
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name        = "${var.name_prefix}-grafana-admin"
  description = "Grafana admin password (monitoring server, E11)"

  # 세션마다 만들고 지운다. 복구 대기 기간이 있으면 다음 세션에 같은 이름을 못 만든다(db 비밀과 같은 이유)
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = random_password.grafana_admin.result
}

# ---------- 인스턴스 역할 ----------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name                 = "${var.name_prefix}-prometheus"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.permissions_boundary_arn
}

data "aws_iam_policy_document" "server" {
  # Prometheus ec2_sd_configs: 수집 대상 인스턴스 조회. 조회 API라 리소스 수준 권한이 없다
  statement {
    sid       = "DiscoverScrapeTargets"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }

  # 부팅 때 user data가 Grafana 관리자 비밀번호를 읽는다
  statement {
    sid       = "ReadGrafanaAdminSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.grafana_admin.arn]
  }

  # Grafana 알림 → 기존 알람 토픽(DEC-58, #95)
  statement {
    sid       = "PublishAlertsToTopic"
    actions   = ["sns:Publish", "sns:GetTopicAttributes"]
    resources = [var.alarm_topic_arn]
  }

  # 토픽이 KMS로 암호화돼 게시자에게 키 권한이 필요하다. SNS를 거친 호출만, 키는 boundary가 alerts 키로 한정한다
  statement {
    sid       = "AlertTopicKeyViaSns"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${var.region}.amazonaws.com"]
    }
  }

  # Grafana CloudWatch 데이터 소스(ALB·RDS 패널). 읽기 API라 리소스 수준 권한이 없다
  statement {
    sid = "CloudWatchRead"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "prometheus-server"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

# SSM Session Manager(포트 포워딩 접속, DEC-57). 공인 IP·SSH 키·인바운드 규칙 없이 들어간다
resource "aws_iam_role_policy_attachment" "server_ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.name_prefix}-prometheus"
  role = aws_iam_role.server.name
}

# 관제 VPC의 인터넷 경로(사설 기본 경로·연결, 퍼블릭 경로·연결)에 대한 의존 자리표
resource "terraform_data" "network_egress" {
  input = var.network_egress_dependency_ids
}

# 운영 VPC의 Cloud Map 비공개 존을 관제 VPC에도 연결해, Prometheus가 앱 태스크 이름을 풀게 한다(#94, DEC-55).
# 피어링은 DNS를 넘겨주지 않아(비공개 존은 연결된 VPC에서만 보인다) 존에 관제 VPC를 직접 붙인다
resource "aws_route53_zone_association" "app_discovery" {
  zone_id = var.app_discovery_zone_id
  vpc_id  = var.vpc_id
}

# ---------- 서버 ----------
resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.prometheus.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  # IMDSv2만. 컨테이너는 host 네트워크라 홉 1로 인스턴스 역할 자격 증명을 받는다
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # OS·이미지·지표(보존 15일 설정, 실제로는 세션 동안만, DEC-59)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # 대시보드·알림 설정까지 넣으면 16 KB 상한에 가까워 gzip으로 보낸다(cloud-init이 풀어서 실행한다)
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region              = var.region
    grafana_secret_id   = aws_secretsmanager_secret.grafana_admin.name
    prometheus_image    = var.prometheus_image
    grafana_image       = var.grafana_image
    node_exporter_image = var.node_exporter_image
    compose_version     = var.compose_version
    scrape_interval     = var.scrape_interval
    retention           = var.retention
    target_asg_names    = jsonencode(var.target_asg_names)
    app_dns_name        = var.app_discovery_dns_name
    app_metrics_port    = var.app_metrics_port
    node_exporter_port  = var.node_exporter_port
    cadvisor_port       = var.cadvisor_port
    dashboard_json      = file("${path.module}/templates/grafana/dashboard.json")
    alerting_yaml = templatefile("${path.module}/templates/grafana/alerting.yaml.tftpl", {
      alarm_topic_arn       = var.alarm_topic_arn
      region                = var.region
      app_cpu_reservation   = var.app_cpu_reservation
      cpu_warning_percent   = var.cpu_warning_percent
      cpu_critical_percent  = var.cpu_critical_percent
      db_identifier         = var.db_identifier
      rds_storage_low       = var.rds_storage_low_bytes
      rds_connections_high  = var.rds_connections_high
      http_5xx_rate_percent = var.http_5xx_rate_percent
      http_5xx_min_requests = var.http_5xx_min_requests
    })
  }))
  user_data_replace_on_change = true

  tags = { Name = "${var.name_prefix}-prometheus" }

  # 부팅 스크립트가 처음부터 밖으로 나갈 수 있어야 한다: 비밀 값, 역할 정책, 443 아웃바운드 규칙, 관제 VPC의 인터넷 경로(NAT·라우트·연결).
  # 경로 의존은 destroy 때도 서버가 NAT보다 먼저 지워지게 한다(#108과 같은 이유)
  depends_on = [
    aws_secretsmanager_secret_version.grafana_admin,
    aws_iam_role_policy.server,
    aws_vpc_security_group_egress_rule.https_out,
    terraform_data.network_egress,
    aws_route53_zone_association.app_discovery,
  ]

  lifecycle {
    # AMI 파라미터가 새 버전을 가리켜도 떠 있는 서버를 바꾸지 않는다(세션마다 새로 만들 때 최신을 쓴다)
    ignore_changes = [ami]
  }
}
