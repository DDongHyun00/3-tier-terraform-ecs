# 결정 기록 (ADR)

이 프로젝트에서 내린 결정 가운데 대표적인 9건이다. 문서마다 배경, 선택지, 결정, 결과 순서로 적었다.

| 번호 | 결정 | 결과 |
|---|---|---|
| DEC-14 | [사람 인증은 IAM Identity Center와 MFA로, 영구 키 0개](0014-identity-center-mfa.md) | 이 프로젝트에서 영구 액세스 키를 쓰는 주체가 없다 |
| DEC-24 | [배포 역할을 서비스별 정책과 permissions boundary로 좁혔다](0024-deploy-role-least-privilege.md) | 관리자 권한을 떼고도 apply와 배포가 AccessDenied 없이 돈다 |
| DEC-25 | [배포와 롤백 시간을 운영 환경에서 실제 배포로 쟀다](0025-deploy-rollback-measurement.md) | 자동 롤백 5분 19초 동안 응답 217회가 모두 200 |
| DEC-31 | [배포 이미지 빌드 캐시를 mode=max에서 mode=min으로 바꿨다](0031-build-cache-mode-min.md) | 코드 변경 빌드가 3분 58초에서 1분 19초로 줄었다 |
| DEC-32 | [ECS CPU와 RDS 연결 알람은 결측을 missing으로 두고 5분 중 3분으로 평가했다](0032-alarm-missing-data-3-of-5.md) | 울리지 않던 CPU 알람이 과부하 5분 15초 만에 울렸다 |
| DEC-36 | [컴퓨트를 Fargate에서 ECS on EC2로 바꿨다](0036-fargate-to-ecs-on-ec2.md) | 비용은 2% 차이, 호스트 관측과 두 단계 스케일링을 얻었다 |
| DEC-40 | [VPC를 관제, 운영, 스테이징 3개로 나누고 피어링으로 이었다](0040-three-vpcs-peering.md) | 관제와 운영의 장애 영역이 나뉘었다. 피어링은 관제와 운영 1개만 만들었다 |
| DEC-46 | [태스크 사양을 0.25 vCPU / 0.5 GB에서 0.5 vCPU / 1 GB로 올렸다](0046-task-size-upgrade.md) | 앱 기동이 약 122초에서 23초로 줄었다 |
| DEC-67 | [태스크 하나를 Spot으로 돌리고 관측 서버는 끌 수 있게 했다](0067-spot-capacity-mix.md) | 컴퓨트 15% 절감, Spot 회수 때 요청 실패 0건 |
