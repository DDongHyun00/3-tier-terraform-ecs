# 알람 알림 경로 (#38): CloudWatch 알람 → SNS 토픽 3tier-prod-alarms → Amazon Q Developer in chat applications → Slack #aws-alerts.
# main이 아니라 bootstrap에 둔 이유(직접 결정, 10/29):
#   Q Developer 채널 설정을 만들면 Q Developer가 토픽에 구독을 건다. 토픽을 main에 두면 destroy 때 구독이 같이 지워지고
#   다시 apply해도 되살아나지 않는다. 그래서 토픽과 채널 설정을 함께 상시 유지하고, main 알람은 토픽을 이름으로 찾는다.
#   배포 역할에 IAM 역할 생성·Q Developer 권한을 새로 주지 않아도 된다(#35 최소 권한 유지).
# 사전 작업(콘솔, 1회): Q Developer 콘솔(us-east-2)에서 Slack 워크스페이스 인증, 채널에 /invite @Amazon Q.

locals {
  alarm_topic_name = "${local.main_prefix}-alarms" # main 알람이 data 소스로 찾는 이름. 배포 역할 SNS 권한(3tier-prod-*) 범위
}

# ---------- 토픽 암호화 키 ----------
# CloudWatch 알람은 AWS 관리형 키(aws/sns)로 암호화된 토픽에 발행하지 못한다. 고객 관리형 키를 쓰고
# 키 정책에서 cloudwatch.amazonaws.com에 데이터 키 생성·복호화를 허용한다(직접 결정, 10/29).
data "aws_iam_policy_document" "alerts_key" {
  # 계정의 IAM 정책으로 키 권한을 관리한다(기본 키 정책과 같은 문장). 없으면 키를 아무도 관리할 수 없게 된다
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account}:root"]
    }
  }

  # 이 계정의 CloudWatch 알람이 토픽에 발행할 때만. 다른 계정 알람이 이 키를 쓰는 경로(혼동된 대리인)를 막는다
  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${local.region}:${local.account}:alarm:*"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description         = "SNS topic ${local.alarm_topic_name} encryption (#38)"
  enable_key_rotation = true # 1년마다 키 material 자동 교체
  policy              = data.aws_iam_policy_document.alerts_key.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/3tier-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

# ---------- SNS 토픽 ----------
# 토픽 정책은 기본값(같은 계정 주체만 발행)을 쓴다. 같은 계정 CloudWatch 알람은 기본 정책으로 발행된다
resource "aws_sns_topic" "alarms" {
  name              = local.alarm_topic_name
  kms_master_key_id = aws_kms_key.alerts.arn
}

# ---------- Q Developer 채널 ----------
# 채널 역할: Q Developer가 알림 카드에 지표 그래프·로그를 붙일 때 쓴다. 읽기 전용
data "aws_iam_policy_document" "chatbot_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  name               = "3tier-chatbot"
  description        = "Amazon Q Developer in chat applications channel role (#38)"
  assume_role_policy = data.aws_iam_policy_document.chatbot_trust.json
}

resource "aws_iam_role_policy_attachment" "chatbot_cloudwatch_read" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Q Developer API는 us-east-2·us-west-2·ap-southeast-1·eu-west-1에만 있다. 설정만 us-east-2에 두고 서울 토픽을 연결한다
resource "aws_chatbot_slack_channel_configuration" "alerts" {
  region             = "us-east-2"
  configuration_name = "3tier-alerts"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  sns_topic_arns     = [aws_sns_topic.alarms.arn]

  # 지정하지 않으면 AdministratorAccess가 가드레일로 붙어 채널에서 쓰기 명령이 가능해진다. 채널 역할과 같은 읽기 전용으로 제한
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]
  logging_level         = "ERROR"
}
