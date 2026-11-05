# ECS on EC2 용량(#87, DEC-50). 시작 템플릿 → ASG → 용량 공급자 → 클러스터 기본 전략.
# t3.small(2 vCPU, 2 GiB, 네트워크 카드 3개)에는 awsvpc 앱 태스크(1 GB)가 1개만 들어가서,
# 태스크가 2→4로 늘면 용량 공급자가 인스턴스도 2→4로 늘린다(#89 2단계 오토스케일링).

# ECS 최적화 Amazon Linux 2023 최신 권장 AMI(공개 SSM 파라미터, DEC-50 D6)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# provider default_tags는 ASG가 띄우는 인스턴스·볼륨에 붙지 않아 시작 템플릿에서 직접 붙인다(비용 태그)
data "aws_default_tags" "current" {}

# 인스턴스 기본 네트워크 카드용. 들어오는 규칙 없음(접속은 SSM), 나가는 것은 NAT로(ECS·ECR·SSM 엔드포인트)
resource "aws_security_group" "ecs_instance" {
  name        = "${var.name_prefix}-sg-ecs-instance"
  description = "ECS container instances: no ingress, egress for agent and SSM"
  vpc_id      = var.vpc_id

  egress {
    description = "ECS agent, ECR, SSM over NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-ecs-instance" }
}

resource "aws_launch_template" "ecs" {
  name          = "${var.name_prefix}-ecs"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_instance.id]

  # 이 클러스터에 등록. awsvpc 태스크가 인스턴스 메타데이터(인스턴스 역할 자격 증명)에 닿지 못하게 막는다
  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CONF'
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_AWSVPC_BLOCK_IMDS=true
    CONF
  EOT
  )

  # IMDSv2만 허용
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # t3는 버스트형. 부하 시험 중 기준선(vCPU당 20%)을 넘어도 스로틀링하지 않게 unlimited 명시(DEC-50 D2)
  credit_specification {
    cpu_credits = "unlimited"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(data.aws_default_tags.current.tags, { Name = "${var.name_prefix}-ecs-instance" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(data.aws_default_tags.current.tags, { Name = "${var.name_prefix}-ecs-instance" })
  }
}

# 사설 서브넷의 인터넷 경로(NAT·라우트·연결) 전체에 대한 의존 관계만 표현하는 자리표. ECS 서비스와 ASG가 이것에 depends_on 하면
# apply 때는 NAT 경로가 먼저 만들어지고, destroy 때는 서비스·ASG(태스크 정지·인스턴스 종료 보고)가 끝난 뒤에 NAT가 지워진다.
# 모듈 전체 depends_on을 쓰지 않는 이유: AMI 데이터 소스까지 apply로 미뤄져 시작 템플릿에 매번 변경이 뜬다.
resource "terraform_data" "network_egress" {
  input = var.network_egress_dependency_ids
}

# Spot을 켜면 ASG가 둘이 되고 각각 1대씩이라, ASG마다 따로 AZ를 고르면 두 대가 같은 AZ에 뜰 수 있다(11/05 실제로 둘 다 2a).
# ASG는 자기 안에서만 AZ를 고르게 나누므로, 온디맨드는 첫 AZ, Spot은 둘째 AZ 서브넷만 쓰게 나눠 항상 다른 AZ에 둔다(DEC-50 D4 AZ 분산 유지).
# 대가: 한 AZ가 장애면 그 AZ 담당 ASG는 다른 AZ로 옮겨 띄우지 못한다. 다른 AZ의 1대가 남아 서비스는 이어진다
locals {
  on_demand_subnet_ids = var.enable_spot ? [var.private_subnet_ids[0]] : var.private_subnet_ids
  spot_subnet_ids      = var.enable_spot ? [var.private_subnet_ids[1]] : []
}

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name_prefix}-ecs-asg"
  vpc_zone_identifier = local.on_demand_subnet_ids
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  # 관리형 종료 보호(용량 공급자)가 태스크가 있는 인스턴스를 축소에서 지키려면 필요하다
  protect_from_scale_in = true

  # destroy 때 축소 보호가 걸린 인스턴스까지 종료하고 지운다
  force_delete = true

  # 용량 공급자 관리형 스케일링이 요구하는 태그
  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-ecs-instance"
    propagate_at_launch = true
  }

  # 원하는 수는 용량 공급자가 바꾼다. Terraform이 되돌리지 않게 무시
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [terraform_data.network_egress]
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.name_prefix}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn

    # 태스크가 있는 인스턴스는 축소에서 보호하고, 종료되는 인스턴스는 태스크를 옮긴 뒤 끈다(DEC-50 D5)
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
      instance_warmup_period    = 300 # 기본값, 변경 가능. #89에서 실측 기동 시간을 보고 다듬는다
    }
  }
}

# ---------- Spot 용량 (E09 #46, DEC-67) ----------
# 온디맨드 ASG는 그대로 두고 Spot ASG·용량 공급자를 하나 더 둔다. 서비스 전략은 온디맨드 base 1 + 나머지 Spot.
# 시작 템플릿은 같은 것을 쓰고 인스턴스 타입만 여러 개로 열어 둔다(Spot 풀이 마를 때 대비, 둘 다 2 GiB라 태스크 1개/대 그대로).
# Spot 회수 예고(2분)는 관리형 인스턴스 드레이닝이 받아 태스크를 다른 인스턴스로 옮긴다(ECS_ENABLE_SPOT_INSTANCE_DRAINING 불필요).
resource "aws_autoscaling_group" "spot" {
  count = var.enable_spot ? 1 : 0

  name                = "${var.name_prefix}-ecs-spot-asg"
  vpc_zone_identifier = local.spot_subnet_ids
  min_size            = 0
  max_size            = var.spot_asg_max_size

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      # 가격과 남은 용량을 같이 보는 할당. AWS가 Spot 기본 권장으로 안내한다(회수 가능성 낮은 풀 우선)
      spot_allocation_strategy = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs.id
        version            = aws_launch_template.ecs.latest_version
      }

      dynamic "override" {
        for_each = var.spot_instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  protect_from_scale_in = true
  force_delete          = true

  # 용량 재조정: 회수 2분 예고보다 먼저 오는 "회수 위험 높음"(rebalance recommendation) 신호에 새 인스턴스를 먼저 띄우고,
  # 새 인스턴스가 서비스에 들어간 뒤 위험한 인스턴스를 종료한다(종료는 수명 주기 훅 → 관리형 드레이닝이 태스크를 옮긴다).
  # 11/05 첫 실측: 이 설정 없이 회수 예고를 받으면 대신할 인스턴스가 2분 안에 준비되지 않아 504 13건(약 12초)
  capacity_rebalance = true

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-ecs-spot-instance"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [terraform_data.network_egress]
}

resource "aws_ecs_capacity_provider" "spot" {
  count = var.enable_spot ? 1 : 0
  name  = "${var.name_prefix}-spot"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.spot[0].arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"

    # 여유 용량(헤드룸): 목표 사용률을 100보다 낮추면 ASG가 빈 인스턴스를 남겨 둔다(ECS ManagedScaling targetCapacity).
    # 인스턴스당 태스크 1개라 50이면 Spot 태스크 1개당 인스턴스 2대. 회수 예고(2분) 때 새 인스턴스 부팅을 기다리지 않고 빈 인스턴스로 바로 옮긴다.
    # 11/05 실측: 100에서는 대신할 태스크 healthy까지 2분 16초(용량 재조정 켬)~3분 53초가 걸려 회수 전에 못 옮겼다(504 13~18건)
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = var.spot_target_capacity
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
      instance_warmup_period    = 300
    }
  }
}

locals {
  # 서비스·클러스터 기본 전략. Spot을 켜면 온디맨드 base(1개)를 먼저 채우고 나머지는 모두 Spot
  # (base는 한 공급자에만 둘 수 있고 weight보다 먼저 채워진다. 온디맨드 weight 0 = base 뒤로는 온디맨드에 놓지 않음)
  capacity_provider_strategy = var.enable_spot ? [
    { capacity_provider = aws_ecs_capacity_provider.ec2.name, base = var.on_demand_base, weight = 0 },
    { capacity_provider = aws_ecs_capacity_provider.spot[0].name, base = 0, weight = 1 },
    ] : [
    { capacity_provider = aws_ecs_capacity_provider.ec2.name, base = 0, weight = 1 },
  ]
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = concat([aws_ecs_capacity_provider.ec2.name], aws_ecs_capacity_provider.spot[*].name)

  dynamic "default_capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      base              = default_capacity_provider_strategy.value.base
      weight            = default_capacity_provider_strategy.value.weight
    }
  }
}
