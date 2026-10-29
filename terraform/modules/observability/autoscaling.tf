# ECS Service Auto Scaling (#39). 서비스 평균 CPU를 목표(60%) 근처로 유지하도록 태스크 수를 2~4개 사이에서 바꾼다.
# 목표 추적 정책은 Application Auto Scaling이 알람 2개(TargetTracking-service/...-AlarmHigh/-AlarmLow)를 직접 만든다.
#   늘림: 1분 지표 3개 연속 목표 초과 → 부하 시작 후 약 3~4분
#   줄임: 1분 지표 15개 연속 목표의 90% 미만 → 부하 종료 후 약 15~20분
# 서비스의 desired_count는 이 정책이 바꾸므로 Terraform은 무시한다(modules/compute/ecs.tf ignore_changes).

resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  # 클러스터·서비스 이름을 참조해 의존 순서를 만든다. destroy 때 대상 해제가 서비스 삭제보다 먼저 일어난다
  resource_id  = "service/${var.cluster_name}/${var.service_name}"
  min_capacity = var.autoscaling_min
  max_capacity = var.autoscaling_max
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.name_prefix}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  resource_id        = aws_appautoscaling_target.ecs.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
    disable_scale_in   = false

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
