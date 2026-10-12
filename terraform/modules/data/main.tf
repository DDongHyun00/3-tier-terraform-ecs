# RDS PostgreSQL 16 (Single-AZ, DB 서브넷, 외부 접근 불가) + 비밀번호는 Secrets Manager.
# 설계: docs/architecture.md 6.2절. 결정: DEC-1(PostgreSQL), DEC-7(Single-AZ).

# ---------- DB 서브넷 그룹 ----------
# RDS는 서브넷 그룹에 최소 2개 AZ를 요구한다. Single-AZ여도 2개를 넣는다.
resource "aws_db_subnet_group" "this" {
  # RDS 계열 이름(식별자, 서브넷 그룹)은 첫 글자가 영문이어야 한다. "db-" 접두사를 앞에 둔다.
  name       = "db-${var.name_prefix}-subnets"
  subnet_ids = var.db_subnet_ids
  tags       = { Name = "${var.name_prefix}-db-subnets" }
}

# ---------- 비밀번호 ----------
# 코드·tfvars 어디에도 평문이 없다. Terraform이 만들어 Secrets Manager에 넣고,
# ECS 태스크 실행 역할이 기동 때 읽어 환경 변수로 주입한다.
# state 파일에는 남으므로 state 버킷 접근 제한이 곧 비밀번호 보호다.
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?" # RDS가 금지하는 / @ " 공백 제외
}

resource "aws_secretsmanager_secret" "db" {
  name        = "${var.name_prefix}-db-credentials"
  description = "RDS master credentials for ${var.name_prefix}"

  # 기본값(30일)이면 destroy 후 같은 이름으로 다시 만들 때 "scheduled for deletion"으로 막힌다.
  # 매일 destroy/apply하는 환경이라 즉시 삭제로 둔다.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

# ---------- RDS 인스턴스 ----------
resource "aws_db_instance" "this" {
  # RDS 식별자는 첫 글자가 영문이어야 한다. "3tier-..."는 거부되므로 이 리소스만 "db-" 접두사를 앞에 둔다.
  # 태그 Name은 규칙대로 3tier-prod-db.
  identifier = "db-${var.name_prefix}"

  engine                     = "postgres"
  engine_version             = var.engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  # 배치: DB 서브넷 + sg-db. 퍼블릭 IP 없음.
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # 운영 설정. 반복 destroy 전제라 삭제 보호 off, 최종 스냅샷 생략.
  backup_retention_period = var.backup_retention_days
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  # 비용: Performance Insights·Enhanced Monitoring은 끔. CloudWatch 기본 지표로 충분.
  performance_insights_enabled = false

  tags = { Name = "${var.name_prefix}-db" }
}
