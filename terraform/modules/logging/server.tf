# ELK 서버: Elasticsearch·Kibana 단일 노드를 docker compose로 올리는 EC2 1대(E12 #97).
# 관제 서버(modules/monitoring/server.tf)와 같은 틀: AL2023 arm64, IMDSv2, SSM 접속, 비밀은 Secrets Manager, 세션마다 생성·삭제.

data "aws_caller_identity" "current" {}

locals {
  # 배포 역할은 boundary가 붙은 역할만 만들 수 있다(#35)
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/3tier-ecs-boundary"
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------- 비밀: elastic 관리자, fluentbit 쓰기 전용 사용자 ----------
# 셸·.env·Fluent Bit 설정에서 따옴표 처리 없이 쓰려고 영숫자만
resource "random_password" "elastic" {
  length  = 24
  special = false
}

resource "random_password" "fluentbit" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "elastic" {
  name                    = "${var.name_prefix}-elastic"
  description             = "Elasticsearch elastic superuser password (ELK server, E12)"
  recovery_window_in_days = 0 # 세션마다 같은 이름으로 다시 만든다
}

resource "aws_secretsmanager_secret_version" "elastic" {
  secret_id     = aws_secretsmanager_secret.elastic.id
  secret_string = random_password.elastic.result
}

# Fluent Bit가 쓰는 계정. 앱 로그 인덱스에 문서 추가·인덱스 생성만 한다(서버 부팅 때 역할·사용자를 만든다)
resource "aws_secretsmanager_secret" "fluentbit" {
  name                    = "${var.name_prefix}-elastic-fluentbit"
  description             = "Elasticsearch user for Fluent Bit (write-only to app log indices, E12)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "fluentbit" {
  secret_id     = aws_secretsmanager_secret.fluentbit.id
  secret_string = random_password.fluentbit.result
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
  name                 = "${var.name_prefix}-elk"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.permissions_boundary_arn
}

data "aws_iam_policy_document" "server" {
  # 부팅 때 user data가 두 비밀번호를 읽어 Elasticsearch 사용자를 만든다
  statement {
    sid       = "ReadElkSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.elastic.arn, aws_secretsmanager_secret.fluentbit.arn]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "elk-server"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

# SSM Session Manager(Kibana 포트 포워딩 접속)
resource "aws_iam_role_policy_attachment" "server_ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.name_prefix}-elk"
  role = aws_iam_role.server.name
}

resource "terraform_data" "network_egress" {
  input = var.network_egress_dependency_ids
}

# ---------- 서버 ----------
# 사설 IP를 고정한다(#144). FireLens 출력 주소(Host)가 이 IP라, 서버가 교체되면 태스크 정의는 새 리비전이 되지만
# 서비스가 task_definition 변경을 무시해 떠 있는 태스크는 옛 IP로 계속 보낸다. 고정하면 서버를 바꿔도 주소가 같다
data "aws_subnet" "server" {
  id = var.subnet_id
}

resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = cidrhost(data.aws_subnet.server.cidr_block, var.private_ip_hostnum)
  vpc_security_group_ids = [aws_security_group.elk.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region              = var.region
    elastic_secret_id   = aws_secretsmanager_secret.elastic.name
    fluentbit_secret_id = aws_secretsmanager_secret.fluentbit.name
    elasticsearch_image = var.elasticsearch_image
    kibana_image        = var.kibana_image
    compose_version     = var.compose_version
    es_heap             = var.es_heap
    log_index_prefix    = var.log_index_prefix
  }))
  user_data_replace_on_change = true

  tags = { Name = "${var.name_prefix}-elk" }

  # 부팅 스크립트가 처음부터 밖으로 나갈 수 있어야 하고, destroy 때는 NAT보다 먼저 지워져야 한다(#108과 같은 이유)
  depends_on = [
    aws_secretsmanager_secret_version.elastic,
    aws_secretsmanager_secret_version.fluentbit,
    aws_iam_role_policy.server,
    aws_vpc_security_group_egress_rule.https_out,
    terraform_data.network_egress,
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}
