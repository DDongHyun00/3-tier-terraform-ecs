# CloudWatch 대시보드 (#37). ALB·ECS·RDS 핵심 지표 9개를 한 화면에 둔다.
# 한 줄에 한 계층(ALB / ECS / RDS), 위젯 3개씩. 모든 위젯은 1분 기간.

locals {
  # 기준선. 값의 출처는 docs/architecture.md 6.1절(오토스케일링 목표)과 이슈 #38(스토리지 알람)
  cpu_target_percent    = 60
  rds_storage_low_bytes = 2 * 1024 * 1024 * 1024

  widget_width  = 8
  widget_height = 6
  period        = 60

  alb = ["LoadBalancer", var.alb_arn_suffix]
  ecs = ["ClusterName", var.cluster_name, "ServiceName", var.service_name]
  rds = ["DBInstanceIdentifier", var.db_identifier]

  # 행 순서대로. metrics의 마지막 원소(맵)는 선마다 통계·이름을 정한다
  widgets = [
    # ---------- ALB ----------
    {
      title = "ALB 요청 수 (분당)"
      metrics = [
        concat(["AWS/ApplicationELB", "RequestCount"], local.alb, [{ stat = "Sum", label = "요청" }]),
      ]
    },
    {
      title = "ALB 5xx (분당)"
      metrics = [
        concat(["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count"], local.alb, [{ stat = "Sum", label = "ALB가 만든 5xx" }]),
        concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb, [{ stat = "Sum", label = "앱이 돌려준 5xx" }]),
      ]
    },
    {
      title = "ALB 응답 시간 (초)"
      metrics = [
        concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb, [{ stat = "p95", label = "p95" }]),
        concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb, [{ stat = "p50", label = "p50" }]),
      ]
    },
    # ---------- ECS ----------
    {
      title = "ECS CPU (%)"
      metrics = [
        concat(["AWS/ECS", "CPUUtilization"], local.ecs, [{ stat = "Average", label = "서비스 평균" }]),
      ]
      line = { value = local.cpu_target_percent, label = "오토스케일링 목표 ${local.cpu_target_percent}%" }
    },
    {
      title = "ECS 메모리 (%)"
      metrics = [
        concat(["AWS/ECS", "MemoryUtilization"], local.ecs, [{ stat = "Average", label = "서비스 평균" }]),
      ]
    },
    {
      # Container Insights 지표(클러스터 설정에서 켬, modules/compute/ecs.tf)
      title = "ECS 태스크 수"
      metrics = [
        concat(["ECS/ContainerInsights", "RunningTaskCount"], local.ecs, [{ stat = "Average", label = "실행 중" }]),
        concat(["ECS/ContainerInsights", "DesiredTaskCount"], local.ecs, [{ stat = "Average", label = "원하는 수" }]),
      ]
    },
    # ---------- RDS ----------
    {
      title = "RDS CPU (%)"
      metrics = [
        concat(["AWS/RDS", "CPUUtilization"], local.rds, [{ stat = "Average", label = "CPU" }]),
      ]
    },
    {
      title = "RDS 연결 수"
      metrics = [
        concat(["AWS/RDS", "DatabaseConnections"], local.rds, [{ stat = "Maximum", label = "연결" }]),
      ]
    },
    {
      title = "RDS 여유 스토리지 (바이트)"
      metrics = [
        concat(["AWS/RDS", "FreeStorageSpace"], local.rds, [{ stat = "Minimum", label = "여유 공간" }]),
      ]
      line = { value = local.rds_storage_low_bytes, label = "알람 기준 2 GB" }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    # 열었을 때 보이는 기간. 세션 하나(약 2시간)가 한 화면에 들어오게
    start = "-PT3H"

    widgets = [
      for i, w in local.widgets : {
        type   = "metric"
        x      = (i % 3) * local.widget_width
        y      = floor(i / 3) * local.widget_height
        width  = local.widget_width
        height = local.widget_height

        properties = merge(
          {
            title   = w.title
            region  = var.region
            view    = "timeSeries"
            stacked = false
            period  = local.period
            metrics = w.metrics
            yAxis   = { left = { min = 0 } }
          },
          try({ annotations = { horizontal = [w.line] } }, {}),
        )
      }
    ]
  })
}
