# 계정에 한 번 있으면 되는 서비스 연결 역할. main이 세션마다 만들고 지우는 리소스가 처음 쓸 때 AWS가 자동으로 만들려 하지만,
# 배포 역할에는 iam:CreateServiceLinkedRole 권한이 없어 그 자동 생성이 막힌다. 그래서 bootstrap(사람 권한으로 apply)에서 미리 만든다.

# 리전 NAT 게이트웨이(DEC-41, #91). VPC가 이 역할로 EIP 연결·해제와 네트워크 인터페이스 조회를 한다.
# 11/04 main apply가 "not authorized to create service-linked role for regional NAT Gateways"로 실패해 추가했다.
# 출처: Amazon VPC 사용 설명서 "Using service-linked roles for VPC"(AWSServiceRoleForNATGateway, ec2-nat-gateway.amazonaws.com)
resource "aws_iam_service_linked_role" "nat_gateway" {
  aws_service_name = "ec2-nat-gateway.amazonaws.com"
  description      = "Regional NAT gateway (3-tier-terraform-ecs E11)"
}
