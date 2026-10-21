# ECS 역할 2개. 실행 역할은 "컨테이너를 띄우는 ECS"의 권한, 태스크 역할은 "컨테이너 안 앱 코드"의 권한. (DEC-15 최소 권한)

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------- 실행 역할 ----------
# 이미지 풀(ECR), 로그 쓰기(CloudWatch Logs), 시크릿 주입(Secrets Manager)에 필요한 것만.
resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 관리형 정책에는 Secrets Manager 권한이 없다. 시크릿 1개만 추가로 허용.
data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "read-db-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

# ---------- 태스크 역할 ----------
# 앱이 AWS에 하는 일은 첨부파일 버킷 읽기·쓰기뿐. Secrets Manager 권한은 주지 않는다.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_assets_rw" {
  role       = aws_iam_role.task.name
  policy_arn = var.assets_rw_policy_arn
}
