# 앱 로그 경로(E12 #98). enable_log_router가 켜지면 FireLens: 앱 태스크에 Fluent Bit 사이드카(log_router)를 붙여
# 앱 stdout(ECS JSON, #99)을 관제 VPC의 Elasticsearch로 보낸다. 꺼지면 지금처럼 awslogs → CloudWatch Logs.
#
# 데몬(인스턴스마다 1개, host 모드) 대신 FireLens를 고른 이유:
# - Fluent Bit 설정을 ECS가 logConfiguration에서 만들어 준다. 데몬은 설정 파일을 호스트에 깔아야 하는데 공식 이미지에 셸이 없어 넣을 길이 없다.
# - 비밀번호를 secretOptions로 Secrets Manager에서 받는다(실행 역할). 데몬은 평문 인자로 넘겨야 한다.
# - ECS 메타데이터(클러스터·태스크 ARN·컨테이너 이름)를 레코드에 자동으로 붙인다.
# 대가: 태스크마다 사이드카가 하나씩 뜨고(메모리 예약 50 MiB), 앱 로그는 CloudWatch Logs로 가지 않는다(라우터 자신의 로그만 간다).

locals {
  # 조건식의 두 결과는 타입이 같아야 해서 JSON 문자열로 고른 뒤 되돌린다
  app_log_configuration = jsondecode(var.enable_log_router ? jsonencode({
    logDriver = "awsfirelens"
    options = {
      Name               = "es"
      Host               = var.elasticsearch_host
      Port               = "9200"
      HTTP_User          = "fluentbit"
      Logstash_Format    = "On"
      Logstash_Prefix    = var.log_index_prefix
      Suppress_Type_Name = "On"
      # 앱 JSON에 이미 @timestamp가 있어 Fluent Bit가 붙이는 시각은 다른 이름으로 둔다(겹치면 문서가 거부된다)
      Time_Key        = "ingest_time"
      Retry_Limit     = "5"
      Buffer_Size     = "False"
      Trace_Error     = "On"
      Replace_Dots    = "Off"
      Generate_ID     = "Off"
      Include_Tag_Key = "Off"
    }
    secretOptions = [{ name = "HTTP_Passwd", valueFrom = var.elasticsearch_user_secret_arn }]
    }) : jsonencode({
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.app.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "board"
    }
  }))

  # 로그 라우터가 먼저 떠야 앱의 첫 로그를 받는다
  app_depends_on = jsondecode(var.enable_log_router ? jsonencode({ dependsOn = [{ containerName = "log_router", condition = "START" }] }) : "{}")

  log_router_containers = var.enable_log_router ? [
    {
      name              = "log_router"
      image             = var.log_router_image
      essential         = true
      memoryReservation = 50

      firelensConfiguration = {
        type = "fluentbit"
        options = {
          "enable-ecs-log-metadata" = "true"
          # 이미지에 들어 있는 설정: log 필드의 JSON을 풀어 최상위 필드로 올린다(log.level, http.response.status_code 등)
          "config-file-type"  = "file"
          "config-file-value" = "/fluent-bit/configs/parse-json.conf"
        }
      }

      # 라우터 자신의 로그(전송 오류 등)는 CloudWatch Logs로
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "firelens"
        }
      }
    }
  ] : []
}

# 실행 역할이 Fluent Bit 계정 비밀번호를 읽는다(secretOptions)
data "aws_iam_policy_document" "task_execution_log_router" {
  count = var.enable_log_router ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.elasticsearch_user_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_log_router" {
  count  = var.enable_log_router ? 1 : 0
  name   = "read-log-router-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_log_router[0].json
}
