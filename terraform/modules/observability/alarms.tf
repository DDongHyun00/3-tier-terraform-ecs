# CloudWatch 알람 5개 (#38). 울릴 때와 복구될 때 모두 SNS 토픽(bootstrap)으로 보내고, Q Developer가 Slack #aws-alerts에 올린다.
# 공통: 1분 지표, 데이터가 없으면 정상으로 본다(태스크·트래픽이 없는 시간에 오경보 방지). ECS CPU·RDS 연결 알람만 결측을 missing으로 둔다(#80).

locals {
  alarm_actions = [var.alarm_topic_arn]
}

# ---------- ALB ----------
# ALB가 만든 5xx(502·503·504)와 앱이 돌려준 5xx를 합쳐 요청 대비 비율로 본다.
# 5xx 지표는 발생한 분에만 값이 있어 FILL로 0을 채운다. 요청이 적은 분은 비율을 0으로 둔다(alb_5xx_min_requests)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.name_prefix}-alb-5xx-rate"
  alarm_description   = "ALB 5xx 비율이 ${var.alb_5xx_rate_percent}%를 5분 중 3분 넘었다. 대시보드 ALB 5xx·ECS 태스크 수, 앱 로그 /ecs/${var.name_prefix}-board 확인"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_rate_percent
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "rate"
    label       = "5xx 비율(%)"
    expression  = "IF(FILL(req, 0) >= ${var.alb_5xx_min_requests}, 100 * (FILL(elb5xx, 0) + FILL(target5xx, 0)) / FILL(req, 1), 0)"
    return_data = true
  }

  metric_query {
    id = "req"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "elb5xx"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "target5xx"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      period      = 60
      stat        = "Sum"
    }
  }
}

# 롤링 배포 중 새 태스크는 initial, 빠지는 태스크는 draining이라 unhealthy로 세지 않는다. 헬스체크 실패만 잡는다
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "${var.name_prefix}-alb-unhealthy-targets"
  alarm_description   = "타깃 그룹에 비정상 태스크가 2분 연속 1개 이상. ECS 서비스 이벤트·중지된 태스크의 중지 사유 확인"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { TargetGroup = var.target_group_arn_suffix, LoadBalancer = var.alb_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------- ECS ----------
# ECS 서비스 지표가 평가 시점보다 약 4분 늦게 도착해 notBreaching이면 빈 구간이 정상으로 채워져 5/5가 성립하지 않았다(10/29 부하 시험). 결측은 기본값 missing, 평가는 5분 중 3분으로 바꿨다(#80).
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  alarm_description   = "ECS 서비스 평균 CPU가 ${var.ecs_cpu_high_percent}%를 5분 중 3분 넘었다. 오토스케일링 최대치 도달 여부(태스크 수)와 부하 원인 확인"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  statistic           = "Average"
  period              = 60
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.ecs_cpu_high_percent
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------- RDS ----------
# 스토리지는 천천히 줄어드는 값이라 5분 지표 한 번으로 본다
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-storage-low"
  alarm_description   = "RDS 여유 스토리지가 2 GB 미만. 테이블·로그 크기 확인, 필요하면 allocated_storage 증설"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_storage_low_bytes
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# 앱 HikariCP 풀(기본 10) × 태스크 수가 평소 연결 수다. 태스크 4개에서 롤링 배포(최대 200%)를 하면 8 × 10 = 80으로 한도에 닿는다
# 지표가 늦게 도착하면 notBreaching이 빈 구간을 정상으로 채워 5/5가 성립하지 않는다(10/29 ECS CPU 알람에서 확인). ECS CPU 알람과 같이 결측은 기본값 missing, 평가는 5분 중 3분으로 바꿨다(#80).
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  alarm_description   = "RDS 연결 수가 ${var.rds_connections_high}개를 5분 중 3분 넘었다. 태스크 수·배포 진행 여부, 연결 누수 확인"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Maximum"
  period              = 60
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_connections_high
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
