# 결정 기록 (ADR)

Notion 결정 기록 중 대표 결정 9건을 옮긴 것이다. 전체 기록은 Notion에 있다.

| 번호 | 결정 | 검증 |
| --- | --- | --- |
| DEC-14 | [사람 인증은 IAM Identity Center + MFA, 영구 키 0개](0014-identity-center-mfa.md) | 해당 없음 |
| DEC-24 | [배포 역할을 서비스별 정책 5개와 permissions boundary로 좁혔다](0024-deploy-role-least-privilege.md) | 실측 완료 |
| DEC-25 | [배포·롤백 시간을 운영 환경에서 실제 배포로 측정했다](0025-deploy-rollback-measurement.md) | 실측 완료 |
| DEC-31 | [배포 이미지 빌드 캐시는 mode=max에서 mode=min으로 바꾼다](0031-build-cache-mode-min.md) | 실측 완료 |
| DEC-32 | [ECS CPU·RDS 연결 알람은 결측을 missing으로 두고 5분 중 3분으로 평가한다](0032-alarm-missing-data-3-of-5.md) | 실측 완료 |
| DEC-36 | [컴퓨트를 Fargate에서 ECS on EC2로 전환한다](0036-fargate-to-ecs-on-ec2.md) | 예상 |
| DEC-40 | [VPC는 관제·운영·스테이징 3개로 나누고 Transit Gateway 대신 피어링 2개로 잇는다](0040-three-vpcs-peering.md) | 예상 |
| DEC-46 | [태스크 사양을 0.25 vCPU / 0.5 GB에서 0.5 vCPU / 1 GB로 올린다](0046-task-size-upgrade.md) | 실측 완료 |
| DEC-67 | [운영 태스크 하나를 Spot에 두고(온디맨드 base 1), 대기 Spot 1대와 최소 정상 비율 50%로 회수를 사용자에게 보이지 않게 넘기며, 관측 서버는 변수로 끌 수 있게 한다](0067-spot-capacity-mix.md) | 실측 완료 |
