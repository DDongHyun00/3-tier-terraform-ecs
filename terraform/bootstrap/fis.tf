# DB 연결 장애 재현용 AWS FIS 실험 (#43).
# 실험: DB 서브넷 2개의 NACL을 FIS가 복제해 deny 규칙을 넣고 서브넷에 붙인다. 10분 뒤 복제본을 지우고 원래 NACL로 되돌린다.
# NACL로 끊는 이유: SG 규칙을 지워도 이미 맺은 연결(연결 추적)은 끊기지 않는다. NACL은 상태가 없어 바로 끊긴다(E08 설계 D2).
# main이 아니라 bootstrap에 둔 이유: 실험 역할(IAM)을 배포 역할 권한에 넣지 않으려고. main을 destroy해도 템플릿은 남고,
#   대상 서브넷은 실험을 시작할 때 태그로 찾는다(main을 apply할 때마다 서브넷 ID가 바뀐다).
# 주의: 실험 중에는 main을 destroy하지 않는다. 복제 NACL이 남아 있으면 VPC 삭제가 실패한다.

# ---------- 실험 역할 ----------
# FIS가 이 역할을 수임해 NACL을 만들고 바꾼다. 이 계정의 FIS 실험만 수임할 수 있다(혼동된 대리인 방지)
data "aws_iam_policy_document" "fis_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:fis:${local.region}:${local.account}:experiment/*"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "3tier-fis"
  description        = "AWS FIS experiment role for DB subnet network disruption (#43)"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json
}

# AWS 관리형: NACL 생성·삭제·연결 교체. 생성·삭제는 FIS가 붙이는 managedByFIS=true 태그로 좁혀져 있다
resource "aws_iam_role_policy_attachment" "fis_network" {
  role       = aws_iam_role.fis.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess"
}

# ---------- 실험 템플릿 ----------
# 템플릿에는 이름 인자가 없어 Name 태그로 이름을 붙인다. 시작 명령은 출력 fis_db_disrupt_template_id를 쓴다
resource "aws_fis_experiment_template" "db_disrupt" {
  description = "Deny all traffic to/from ${local.main_prefix} DB subnets for 10 minutes (#43)"
  role_arn    = aws_iam_role.fis.arn

  # 중지 조건 없음. 10분이 지나면 자동 원복하고, 중간에 멈추려면 stop-experiment
  stop_condition {
    source = "none"
  }

  action {
    name      = "disrupt-db-subnets"
    action_id = "aws:network:disrupt-connectivity"

    parameter {
      key   = "duration"
      value = "PT10M"
    }

    # all: 서브넷으로 들어오고 나가는 트래픽 전부 차단(같은 서브넷 안 통신은 허용)
    parameter {
      key   = "scope"
      value = "all"
    }

    target {
      key   = "Subnets"
      value = "db-subnets"
    }
  }

  # modules/network의 DB 서브넷 태그(Tier=db) + provider default_tags의 Project. 태그는 모두 맞아야 대상이 된다
  # main이 destroy 상태면 대상이 없어 실험 시작이 실패한다(빈 대상 기본 동작 fail)
  target {
    name           = "db-subnets"
    resource_type  = "aws:ec2:subnet"
    selection_mode = "ALL"

    resource_tag {
      key   = "Project"
      value = local.project_tag
    }

    resource_tag {
      key   = "Tier"
      value = "db"
    }
  }

  tags = { Name = "3tier-db-disrupt" }
}
