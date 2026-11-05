# ECS 클러스터, 로그 그룹, 태스크 정의, 서비스.

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  # Container Insights: 클러스터·서비스 단위 CPU/메모리 지표. 이를 쓰던 CloudWatch 대시보드는 #95에서 지웠다
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}-board"
  retention_in_days = var.log_retention_days
}

# ---------- 태스크 정의 ----------
# 이미지가 바뀌면 새 리비전이 생긴다. 서비스는 task_definition 변경을 무시하므로(ignore_changes) 롤링 배포는 deploy.yml이 한다.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-board"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # x86으로 빌드한 이미지를 그대로 쓴다(t3, DEC-50 D1). ARM64(Graviton)는 빌드 아키텍처도 맞춰야 한다
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode(concat([
    merge({
      name      = "board"
      image     = var.image
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      # 평문이어도 되는 설정
      environment = [
        { name = "DB_URL", value = var.db_url },
        { name = "STORAGE_TYPE", value = "s3" },
        { name = "S3_BUCKET", value = var.assets_bucket_name },
        { name = "AWS_REGION", value = var.region },
        { name = "JAVA_TOOL_OPTIONS", value = var.java_tool_options },
      ]

      # 실행 역할이 시크릿의 JSON에서 키 하나씩 꺼내 환경 변수로 넣는다. 형식: <시크릿 ARN>:<키>::
      secrets = [
        { name = "DB_USERNAME", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
        { name = "ADMIN_PASSWORD", valueFrom = "${var.db_secret_arn}:admin_password::" },
      ]

      logConfiguration = local.app_log_configuration

      # SIGTERM 뒤 이 시간 안에 안 끝나면 SIGKILL. 앱 graceful 20초보다 길게
      stopTimeout = var.stop_timeout
    }, local.app_depends_on)
  ], local.log_router_containers))
}

# ---------- 서비스 ----------
resource "aws_ecs_service" "app" {
  name            = "${var.name_prefix}-board"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  # Fargate 대신 EC2 용량 공급자(#87). Fargate 구성은 git 태그 v1-fargate에 남아 있다(DEC-50 D9)
  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      base              = capacity_provider_strategy.value.base
      weight            = capacity_provider_strategy.value.weight
    }
  }

  # 떠 있는 서비스의 용량 공급자 전략을 바꿀 때 provider가 요구한다(Fargate → EC2 전환 때 넣었고, 지금은 enable_spot을 켜고 끌 때). ignore_changes로 평소 apply는 서비스를 건드리지 않는다
  force_new_deployment = true

  # AZ에 고르게 나눈 뒤, 각 AZ 안에서는 메모리 기준으로 채운다(DEC-50 D4)
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  # 롤링: 새 태스크를 띄우고(최대 200%) 옛것을 뺀다.
  # 최소 50%: Spot 회수 예고(2분)로 인스턴스가 DRAINING이 되면 옛 태스크를 대체 태스크의 healthy를 기다리지 않고
  # 바로 대상 그룹에서 빼고 멈춘다. 그동안 온디맨드 태스크가 요청을 받는다.
  # 100%일 때는 대체 태스크 healthy까지 기다리다 2분을 넘겨 회수된 인스턴스로 요청이 가 502·504 12건이 났다(#46 3차 측정)
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # 새 태스크가 계속 죽으면 배포를 실패 처리하고 직전 리비전으로 되돌린다 (E08 #42에서 재현)
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # 기동 직후 헬스체크 실패를 무시하는 시간(240초). Fargate 0.25 vCPU 때 실측 기동 120초(로컬 11초)에 맞췄고, 0.5 vCPU로 올린 뒤 기동은 약 23초다(DEC-46).
  # 60초로 뒀다가 태스크가 기동 중에 교체되는 루프가 생겼다 (TS-11)
  health_check_grace_period_seconds = var.health_check_grace_period

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false # 프라이빗 서브넷. 바깥은 NAT로 나간다
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "board"
    container_port   = var.app_port
  }

  # 태스크가 뜨고 지는 대로 Cloud Map에 IP를 등록·해제한다(#94)
  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }

  # 배포는 GitHub Actions가 태스크 정의 새 리비전을 등록하고 서비스를 갱신한다(E06).
  # Terraform이 서비스의 task_definition을 자기 리비전으로 되돌리지 않도록 무시한다.
  # Terraform으로 태스크 정의(CPU·메모리·환경 변수)를 바꾸면 다음 배포 때 그 리비전을 기반으로 반영된다.
  # desired_count는 오토스케일링(#39)이 2~4로 바꾼다. 무시하지 않으면 다음 apply가 늘어난 태스크를 2로 되돌린다.
  # 그래서 var.desired_count는 서비스를 처음 만들 때만 쓰이고, 떠 있는 서비스의 하한은 스케일링 대상의 min이 지킨다.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  # 리스너가 타깃 그룹에 붙기 전에 서비스를 만들면 실패한다. 용량 공급자가 클러스터에 붙은 뒤에 만든다(destroy는 반대 순서)
  # 지표 경로 차단 규칙(#94)이 있은 뒤에 태스크가 ALB 뒤로 들어가게 한다(새로 만들 때).
  # destroy 때 ECS agent가 태스크 정지를 끝까지 보고하려면 네트워크 경로(#108)와 인스턴스 역할의 ECS 권한이 서비스보다 오래 남아야 한다.
  # 11/02 두 번째 destroy에서 ECS 정책 연결이 먼저 지워져 같은 DRAINING 고착이 났다
  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener.http,
    aws_lb_listener_rule.block_metrics,
    aws_ecs_cluster_capacity_providers.this,
    terraform_data.network_egress,
    aws_iam_role_policy_attachment.ecs_instance_agent,
  ]
}
