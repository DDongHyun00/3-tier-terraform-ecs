# 3-Tier 네트워크. VPC 하나, AZ 2곳, 계층별 서브넷(public / private / db), NAT는 AZ마다 1개, SG 3개.
# 설계: docs/architecture.md 5절.

locals {
  az_count = length(var.azs)
}

# ---------- VPC ----------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # RDS 엔드포인트, VPC 엔드포인트가 DNS 이름을 쓴다

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# ---------- 서브넷 ----------
# count 인덱스 i = AZ 순서. 0 → 2a, 1 → 2c.
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # ALB·NAT가 있는 계층만 퍼블릭 IP

  tags = { Name = "${var.name_prefix}-public-${var.az_suffixes[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name_prefix}-private-${var.az_suffixes[count.index]}", Tier = "private" }
}

resource "aws_subnet" "db" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name_prefix}-db-${var.az_suffixes[count.index]}", Tier = "db" }
}

# ---------- NAT (AZ마다 1개) ----------
# 한 AZ의 NAT가 죽어도 다른 AZ의 태스크는 ECR 풀·Secrets 조회를 계속할 수 있다. (DEC-11)
resource "aws_eip" "nat" {
  count  = local.az_count
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${var.az_suffixes[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # NAT 자체는 퍼블릭 서브넷에 산다

  tags = { Name = "${var.name_prefix}-nat-${var.az_suffixes[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------- 라우트 테이블 ----------
# public: 0.0.0.0/0 → IGW. 두 AZ가 하나를 공유한다.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# private: AZ마다 테이블 하나. 0.0.0.0/0 → 같은 AZ의 NAT.
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-private-${var.az_suffixes[count.index]}" }
}

resource "aws_route" "private_nat" {
  count                  = local.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# db: 외부 경로 없음. VPC 안(local) 라우트만. 테이블을 따로 두는 이유는
# "DB 서브넷은 밖으로 나가는 길이 없다"를 라우트 테이블 하나로 증명하기 위해서다.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = local.az_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ---------- Security Group ----------
# 규칙은 별도 리소스(aws_vpc_security_group_*_rule)로 쓴다.
# SG끼리 서로 참조(alb→app, app→db)하는데 inline 규칙으로 쓰면 순환 참조가 된다.
# 소스는 CIDR이 아니라 SG 참조: 태스크 IP는 배포마다 바뀌지만 SG는 바뀌지 않는다.

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-sg-alb"
  description = "ALB: HTTPS/HTTP from internet, to app only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-sg-app"
  description = "ECS tasks: from ALB only, to DB and AWS APIs"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-app" }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-sg-db"
  description = "RDS: from app only, no egress"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-db" }
}

# alb 인바운드: 443, 80 ← 인터넷. 80은 HTTPS로 301 리다이렉트용.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet (redirect to HTTPS)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# alb 아웃바운드: 8080 → app SG만
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To app tasks"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# app 인바운드: 8080 ← alb SG만
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# app 아웃바운드: 5432 → db SG, 443 → 인터넷(NAT 경유 AWS API: ECR, Secrets Manager, CloudWatch, S3)
resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "To RDS"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "To AWS APIs via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# db 인바운드: 5432 ← app SG만. 아웃바운드는 아무것도 없다 (DB가 먼저 연결을 시작할 일이 없다).
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "From app tasks"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}
