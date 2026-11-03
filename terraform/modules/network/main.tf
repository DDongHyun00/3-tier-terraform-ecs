# 3-Tier 네트워크. VPC 하나, AZ 2곳, 계층별 서브넷(public / private / db), NAT, SG 3개.
# 같은 모듈을 운영·관제(·스테이징) VPC에 쓴다(E11 #91). 운영은 리전 NAT 수동 모드, 관제는 영역 NAT 1개(DEC-41·53).
# 설계: docs/architecture.md 5절.

data "aws_region" "current" {}

locals {
  az_count     = length(var.azs)
  public_count = length(var.public_subnet_cidrs)
  db_count     = length(var.db_subnet_cidrs)
  regional_nat = var.nat_mode == "regional"
  nat_id       = local.regional_nat ? aws_nat_gateway.regional[0].id : aws_nat_gateway.single[0].id
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
  count                   = local.public_count
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
  count             = local.db_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name_prefix}-db-${var.az_suffixes[count.index]}", Tier = "db" }
}

# ---------- NAT ----------
# regional: 리전 NAT 게이트웨이 수동 모드. NAT ID 하나가 AZ마다 EIP 1개로 동작해, 한 AZ가 죽어도 다른 AZ의
#   아웃바운드가 산다(DEC-11). 퍼블릭 서브넷이 필요 없고 AWS가 IGW로 가는 라우트 테이블을 자동으로 만든다.
#   수동 모드(availability_zone_address)라 자동 모드의 새 AZ 확장 대기(최대 60분)가 없다(DEC-41).
# single: 영역 NAT 1개(첫 퍼블릭 서브넷). 관제·스테이징처럼 NAT AZ 장애를 감수하는 VPC용.
resource "aws_eip" "nat" {
  count  = local.regional_nat ? local.az_count : 1
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${var.az_suffixes[count.index]}" }
}

resource "aws_nat_gateway" "regional" {
  count             = local.regional_nat ? 1 : 0
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"

  # 이 블록을 빼면 자동 모드로 재생성된다. AZ와 EIP는 순서대로 짝짓는다
  dynamic "availability_zone_address" {
    for_each = var.azs
    content {
      availability_zone = availability_zone_address.value
      allocation_ids    = [aws_eip.nat[availability_zone_address.key].id]
    }
  }

  tags = { Name = "${var.name_prefix}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "single" {
  count         = local.regional_nat ? 0 : 1
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id # 영역 NAT는 퍼블릭 서브넷에 산다

  tags = { Name = "${var.name_prefix}-nat-${var.az_suffixes[0]}" }

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
  count          = local.public_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# private: AZ마다 테이블 하나. 0.0.0.0/0 → NAT(리전 NAT면 두 테이블이 같은 ID). 피어링 경로도 여기에 붙는다.
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-private-${var.az_suffixes[count.index]}" }
}

resource "aws_route" "private_nat" {
  count                  = local.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.nat_id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# db: 외부 경로 없음. VPC 안(local) 라우트만. 테이블을 따로 두는 이유는
# "DB 서브넷은 밖으로 나가는 길이 없다"를 라우트 테이블 하나로 증명하기 위해서다.
resource "aws_route_table" "db" {
  count  = local.db_count > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = local.db_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db[0].id
}

# ---------- S3 게이트웨이 엔드포인트 ----------
# ECR 이미지 레이어는 S3에서 받는다. 사설 라우트 테이블에 S3 경로를 넣어 이 트래픽이 NAT를 거치지 않게 한다.
# 게이트웨이 엔드포인트는 추가 요금이 없고, 피어링으로는 다른 VPC 것을 빌려 쓸 수 없어 VPC마다 단다(DEC-41).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

# ---------- Security Group ----------
# 규칙은 별도 리소스(aws_vpc_security_group_*_rule)로 쓴다.
# SG끼리 서로 참조(alb→app, app→db)하는데 inline 규칙으로 쓰면 순환 참조가 된다.
# 소스는 CIDR이 아니라 SG 참조: 태스크 IP는 배포마다 바뀌지만 SG는 바뀌지 않는다.
# 3계층 SG는 운영·스테이징만. 관제 VPC는 자기 SG를 monitoring 모듈이 만든다(create_tier_security_groups = false).

locals {
  tier_sg_count = var.create_tier_security_groups ? 1 : 0
}

resource "aws_security_group" "alb" {
  count       = local.tier_sg_count
  name        = "${var.name_prefix}-sg-alb"
  description = "ALB: HTTPS/HTTP from internet, to app only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-alb" }
}

resource "aws_security_group" "app" {
  count       = local.tier_sg_count
  name        = "${var.name_prefix}-sg-app"
  description = "ECS tasks: from ALB only, to DB and AWS APIs"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-app" }
}

resource "aws_security_group" "db" {
  count       = local.tier_sg_count
  name        = "${var.name_prefix}-sg-db"
  description = "RDS: from app only, no egress"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-sg-db" }
}

# alb 인바운드: 443, 80 ← 인터넷. 80은 HTTPS로 301 리다이렉트용.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = local.tier_sg_count

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count = local.tier_sg_count

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from internet (redirect to HTTPS)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# alb 아웃바운드: 8080 → app SG만
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  count = local.tier_sg_count

  security_group_id            = aws_security_group.alb[0].id
  description                  = "To app tasks"
  referenced_security_group_id = aws_security_group.app[0].id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# app 인바운드: 8080 ← alb SG만
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  count = local.tier_sg_count

  security_group_id            = aws_security_group.app[0].id
  description                  = "From ALB"
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# app 아웃바운드: 5432 → db SG, 443 → 인터넷(NAT 경유 AWS API: ECR, Secrets Manager, CloudWatch, S3)
resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  count = local.tier_sg_count

  security_group_id            = aws_security_group.app[0].id
  description                  = "To RDS"
  referenced_security_group_id = aws_security_group.db[0].id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  count = local.tier_sg_count

  security_group_id = aws_security_group.app[0].id
  description       = "To AWS APIs via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# db 인바운드: 5432 ← app SG만. 아웃바운드는 아무것도 없다 (DB가 먼저 연결을 시작할 일이 없다).
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  count = local.tier_sg_count

  security_group_id            = aws_security_group.db[0].id
  description                  = "From app tasks"
  referenced_security_group_id = aws_security_group.app[0].id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}
