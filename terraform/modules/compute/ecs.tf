# ECS 클러스터, 로그 그룹, 태스크 정의, 서비스.

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  # Container Insights: 클러스터·서비스 단위 CPU/메모리 지표. E07 대시보드가 쓴다
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
# 이미지 태그가 바뀌면 새 리비전이 생기고 서비스가 롤링 배포한다.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-board"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # 로컬(x86)에서 빌드한 이미지를 그대로 쓴다. ARM64(Graviton)는 빌드 아키텍처도 맞춰야 한다
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
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
      ]

      # 실행 역할이 시크릿의 JSON에서 키 하나씩 꺼내 환경 변수로 넣는다. 형식: <시크릿 ARN>:<키>::
      secrets = [
        { name = "DB_USERNAME", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "board"
        }
      }

      # SIGTERM 뒤 이 시간 안에 안 끝나면 SIGKILL. 앱 graceful 20초보다 길게
      stopTimeout = var.stop_timeout
    }
  ])
}

# ---------- 서비스 ----------
resource "aws_ecs_service" "app" {
  name            = "${var.name_prefix}-board"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # 롤링: 기존 2개를 유지한 채 새 2개를 띄우고(최대 200%), healthy가 되면 옛것을 뺀다
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # 새 태스크가 계속 죽으면 배포를 실패 처리하고 직전 리비전으로 되돌린다 (E08 #42에서 재현)
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # 기동 직후 헬스체크 실패를 무시하는 시간. 0.25 vCPU에서 실측 기동 120초(로컬 11초).
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

  # 리스너가 타깃 그룹에 붙기 전에 서비스를 만들면 실패한다
  depends_on = [aws_lb_listener.https, aws_lb_listener.http]
}
