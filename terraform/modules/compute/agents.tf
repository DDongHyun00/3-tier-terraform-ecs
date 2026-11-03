# 호스트·컨테이너 지표 에이전트: node_exporter·cAdvisor를 ECS 데몬 서비스로 인스턴스마다 1개씩(E11 #93).
# 관제 VPC의 Prometheus가 ec2_sd_configs로 인스턴스를 찾아 사설 IP:9100·8081로 수집한다(DEC-55).
# t3.small ENI 3개로는 앱 awsvpc 태스크 옆에 awsvpc 데몬 2개를 둘 수 없어 host·bridge 모드로 둔다(DEC-56).
# 데몬 서비스는 용량 공급자 전략을 쓸 수 없어 launch_type = EC2로 띄운다. 인스턴스가 늘면 자동으로 따라 뜬다.

resource "aws_cloudwatch_log_group" "agents" {
  count             = var.enable_metrics_agents ? 1 : 0
  name              = "/ecs/${var.name_prefix}-agents"
  retention_in_days = var.log_retention_days
}

# ---------- node_exporter (host 모드) ----------
# 호스트 네트워크·PID 네임스페이스와 루트 파일 시스템(읽기 전용)을 봐야 호스트 지표가 나온다
resource "aws_ecs_task_definition" "node_exporter" {
  count                    = var.enable_metrics_agents ? 1 : 0
  family                   = "${var.name_prefix}-node-exporter"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  pid_mode                 = "host"
  execution_role_arn       = aws_iam_role.task_execution.arn

  volume {
    name      = "rootfs"
    host_path = "/"
  }

  container_definitions = jsonencode([
    {
      name      = "node-exporter"
      image     = var.node_exporter_image
      essential = true
      cpu       = 64
      memory    = 64
      command = [
        "--path.rootfs=/host",
        "--web.listen-address=:${var.node_exporter_port}",
      ]
      portMappings = [{ containerPort = var.node_exporter_port, hostPort = var.node_exporter_port, protocol = "tcp" }]
      mountPoints  = [{ sourceVolume = "rootfs", containerPath = "/host", readOnly = true }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agents[0].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "node-exporter"
        }
      }
    }
  ])
}

# ---------- cAdvisor (bridge 모드, 호스트 8081 → 컨테이너 8080) ----------
# 컨테이너별 CPU·메모리·throttling. Docker 소켓·cgroup·디스크 정보를 읽기 전용으로 마운트하고 privileged로 돈다(cAdvisor 권장 실행 방식)
resource "aws_ecs_task_definition" "cadvisor" {
  count                    = var.enable_metrics_agents ? 1 : 0
  family                   = "${var.name_prefix}-cadvisor"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.task_execution.arn

  volume {
    name      = "rootfs"
    host_path = "/"
  }
  volume {
    name      = "var-run"
    host_path = "/var/run"
  }
  volume {
    name      = "sys"
    host_path = "/sys"
  }
  volume {
    name      = "docker"
    host_path = "/var/lib/docker"
  }
  volume {
    name      = "disk"
    host_path = "/dev/disk"
  }

  container_definitions = jsonencode([
    {
      name       = "cadvisor"
      image      = var.cadvisor_image
      essential  = true
      cpu        = 128
      memory     = 160
      privileged = true
      command = [
        "--docker_only=true",
        "--housekeeping_interval=15s",
        "--disable_metrics=percpu,sched,tcp,udp,disk,diskIO,hugetlb,referenced_memory,cpu_topology,resctrl",
      ]
      portMappings = [{ containerPort = 8080, hostPort = var.cadvisor_port, protocol = "tcp" }]
      mountPoints = [
        { sourceVolume = "rootfs", containerPath = "/rootfs", readOnly = true },
        { sourceVolume = "var-run", containerPath = "/var/run", readOnly = true },
        { sourceVolume = "sys", containerPath = "/sys", readOnly = true },
        { sourceVolume = "docker", containerPath = "/var/lib/docker", readOnly = true },
        { sourceVolume = "disk", containerPath = "/dev/disk", readOnly = true },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agents[0].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "cadvisor"
        }
      }
    }
  ])
}

# ---------- 데몬 서비스 ----------
resource "aws_ecs_service" "node_exporter" {
  count               = var.enable_metrics_agents ? 1 : 0
  name                = "${var.name_prefix}-node-exporter"
  cluster             = aws_ecs_cluster.this.id
  task_definition     = aws_ecs_task_definition.node_exporter[0].arn
  scheduling_strategy = "DAEMON"
  launch_type         = "EC2"

  # 데몬은 인스턴스마다 1개라 교체할 때 먼저 멈추고 새로 띄운다(호스트 포트가 겹쳐 동시에 둘을 못 띄운다)
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # destroy 때 사설 서브넷 인터넷 경로와 인스턴스 역할 ECS 권한보다 먼저 지워지게(#108). 데몬도 ECS agent가 정지를 보고해야 끝난다
  depends_on = [aws_ecs_cluster_capacity_providers.this, terraform_data.network_egress, aws_iam_role_policy_attachment.ecs_instance_agent]
}

resource "aws_ecs_service" "cadvisor" {
  count               = var.enable_metrics_agents ? 1 : 0
  name                = "${var.name_prefix}-cadvisor"
  cluster             = aws_ecs_cluster.this.id
  task_definition     = aws_ecs_task_definition.cadvisor[0].arn
  scheduling_strategy = "DAEMON"
  launch_type         = "EC2"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_ecs_cluster_capacity_providers.this, terraform_data.network_egress, aws_iam_role_policy_attachment.ecs_instance_agent]
}
