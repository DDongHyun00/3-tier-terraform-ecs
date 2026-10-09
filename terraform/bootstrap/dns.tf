# Route 53 호스팅 존은 도메인을 Route 53에서 구매할 때 자동으로 생겼다.
# Terraform이 만들지 않고 data 소스로 읽기만 한다. destroy해도 존은 남는다.
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}
