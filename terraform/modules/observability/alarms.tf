# CloudWatch 비상 알람 2개 (#38, DEC-45·62). 울릴 때와 복구될 때 모두 SNS 토픽(bootstrap)으로 보내고, Q Developer가 Slack #aws-alerts에 올린다.
# 평소 알림(CPU·RDS·전체 중단)은 Grafana가 맡는다(modules/monitoring). 이 2개는 관제 서버가 죽어도 오는 독립 경로로 남긴다.
# ECS CPU·RDS 스토리지·RDS 연결 알람과 CloudWatch 대시보드는 Grafana로 옮기고 지웠다(#95, 11/04 실측 뒤).
# 공통: 1분 지표, 데이터가 없으면 정상으로 본다(태스크·트래픽이 없는 시간에 오경보 방지).

locals {
  alarm_actions = [var.alarm_topic_arn]
}

# ---------- ALB ----------
# ALB가 만든 5xx(502·503·504)와 앱이 돌려준 5xx를 합쳐 요청 대비 비율로 본다.
# 5xx 지표는 발생한 분에만 값이 있어 FILL로 0을 채운다. 요청이 적은 분은 비율을 0으로 둔다(alb_5xx_min_requests)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.name_prefix}-alb-5xx-rate"
  alarm_description   = "ALB 5xx 비율이 ${var.alb_5xx_rate_percent}%를 5분 중 3분 넘었다. Grafana 대시보드와 Kibana(앱 로그)에서 확인"
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
