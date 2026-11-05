# 월 예산과 알림(E09 #44). 계정 단위로 상시 두는 것이라 bootstrap에 둔다.
# 알림 주소는 공개 레포에 남기지 않으려고 변수(terraform.tfvars, 추적 안 함)로 받는다. 비우면 예산을 만들지 않는다.
# 기준: 실제 청구 11/01~04 세션 운영비 시간당 약 0.30 USD(docs/cost.md 8절) + E11·E12 서버로 0.40 USD까지 늘었다.
# 8시간 세션 월 10회면 약 32 USD. 상시 유지분·세금을 더해 월 50 USD를 상한으로 두고 80%·100%에서 알린다.
variable "budget_email" {
  description = "예산 알림 받을 이메일. 비우면 예산을 만들지 않는다(terraform.tfvars에만 적는다)"
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "월 비용 예산(USD, 계정 전체)"
  type        = number
  default     = 50
}

resource "aws_budgets_budget" "monthly" {
  count = var.budget_email == "" ? 0 : 1

  name         = "3tier-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # 실제 지출 80%: 남은 세션 수를 조정할 시점
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  # 실제 지출 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  # 예측 100%: destroy를 잊고 떠 있는 리소스처럼 월말 전에 넘을 흐름을 미리 알린다
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
