# DEC-40. VPC는 관제·운영·스테이징 3개로 나누고 Transit Gateway 대신 피어링 2개로 잇는다

- 상태: 확정 · 날짜: 2026-11-01 · 검증: 예상
- 관련 이슈: https://github.com/DDongHyun00/3-tier-terraform-ecs/issues/91

## 배경

10/30에는 인프라 VPC 하나를 앱 VPC와 피어링하는 VPC 2개 구성으로 정했다(DEC-37). 그런데 VPC가 2개면 관제 서버가 보는 대상이 앱 VPC 하나뿐이라, "왜 같은 VPC에 두지 않고 나눴는가"에 답하기 어려웠다. 현직자 조언도 "VPC 여러 개를 두고 infra 존에서 통합 모니터링"이었다. 그래서 VPC 개수와 연결 방식을 다시 조사했다.

## 결정 요인

- AWS 다중 VPC 백서: 피어링은 연결할 VPC가 10개 미만일 때 가장 적합하고 비용이 가장 낮고 성능이 가장 높다([VPC peering](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/vpc-peering.html)).
- 피어링은 전이 라우팅을 지원하지 않는다. 관제↔운영, 관제↔스테이징만 이으면 운영↔스테이징은 따로 막지 않아도 통하지 않는다([VPC peering 제한](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html)).
- 서울 Transit Gateway 연결 요금은 연결당 시간당 0.07 USD, 데이터 GB당 0.02 USD다(AWS Price List API, 2026-10-16판). 피어링은 시간 요금이 없다.

## 검토한 선택지

- A. 2개 + 피어링(기존): 비용은 그대로지만 "통합"의 근거가 약하다.
- B. 3개 + 피어링: 환경 분리와 공용 서비스 분리를 둘 다 보여 준다.
- C. 3개 + Transit Gateway: 허브 구조지만 3개 규모에서는 백서 기준보다 과하고 연결 요금이 붙는다.

## 결정

B를 골랐다. 관제 VPC 10.100.0.0/16, 운영 10.0.0.0/16, 스테이징 10.1.0.0/16으로 나누고 피어링은 관제↔운영, 관제↔스테이징 2개만 만든다. 보안 그룹은 관제 → 앱 인스턴스 지표 포트, 앱 인스턴스 → 관제 로그 포트만 연다. 관제 VPC에는 인터넷 입구를 두지 않고 SSM으로만 접속한다.

## 결과

- 얻을 것: 관제 한 곳에서 두 환경을 보는 통합 모니터링, 라우팅만으로 생기는 운영·스테이징 격리.
- 감수한 것: VPC가 늘어 세션 비용이 늘어난다. VPC가 10개를 넘거나 NAT를 한 곳에 모아야 하면 Transit Gateway로 옮겨야 한다.
- DEC-37의 "인프라 VPC 분리" 방향은 그대로이고, 개수와 연결 방식을 구체화했다. #91 제목·본문을 고쳤다.

### 실제 구현 (2026-11-05 확인)

관제↔운영 피어링 1개만 만들었다. 관제↔스테이징 피어링은 스테이징 루트(`terraform/staging`, #101)에 넣지 않아 없다. 스테이징은 관제 서버가 보지 않고, 배포 워크플로의 스모크 테스트로 확인한다. VPC 3개와 CIDR 분리, 운영↔스테이징 차단은 설계대로다.
