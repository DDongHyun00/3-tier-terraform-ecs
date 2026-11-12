# DEC-24. 배포 역할을 서비스별 정책과 permissions boundary로 좁혔다

- 상태: 확정
- 날짜: 2026-10-27

## 배경

GitHub OIDC 배포 역할 `3tier-github-deploy`는 처음에 AdministratorAccess로 열어 두고, 실제 호출 기록을 본 뒤 좁히기로 했다. CloudTrail을 보니 이 역할의 세션은 PR의 plan만 돌려서 읽기 작업 67개만 남아 있었다. 쓰기 작업 84개는 같은 Terraform 코드를 로컬 SSO로 apply하고 destroy한 기록(2026-10-20 ~ 10-23)에서 가져왔다. S3 객체, ECR 레이어, PassRole, 태그처럼 기록에 남지 않는 작업은 코드를 읽고 보탰다. 이렇게 모은 151개 작업을 서비스 14개로 나눠 정책을 썼다.

고려한 것:
- IAM 최소 권한은 설계 요구사항이다.
- 배포 역할은 IAM 역할을 만들고 정책을 붙일 수 있어야 한다. 이 권한이 넓으면 역할이 스스로 권한을 키울 수 있다.
- 곧 오토스케일링과 알람도 같은 역할로 apply된다.

## 선택지

| 선택지 | 장점 | 단점 |
|---|---|---|
| IAM 리소스 범위 `3tier-*` | bootstrap 쪽 이름까지 한 패턴으로 묶인다 | 배포 역할 자신과 그 정책도 걸려 스스로 관리자 권한으로 돌아갈 수 있다 |
| 범위 `3tier-prod-*`와 명시적 Deny | main 스택이 만드는 역할과 정책은 모두 이 접두사라 충분하다 | 이름 규칙을 어기면 apply가 막힌다 |
| ECS 역할에 permissions boundary 강제 | 인라인 정책을 붙여 권한을 키우는 경로를 막는다 | ECS 역할을 만들거나 고칠 때마다 boundary 조건을 맞춰야 한다 |
| 오토스케일링과 알람 권한을 미리 넣기 | 다음 단계 첫 apply가 AccessDenied로 막히지 않는다 | 아직 쓰지 않는 권한을 미리 연다 |

## 결정

- AdministratorAccess를 떼고 서비스별 고객 관리형 정책 5개를 붙였다: `3tier-github-deploy-state-ecr`, `-network`, `-compute`, `-data`, `-observability`.
- IAM 작업과 PassRole은 `3tier-prod-*`로 한정하고, 자기 역할과 자기 정책, boundary 정책의 수정은 명시적 Deny로 한 번 더 막았다.
- ECS 역할은 permissions boundary `3tier-ecs-boundary` 아래에서만 만들고 고칠 수 있게 했다.
- EC2, ACM, CloudFront는 ARN 범위를 좁혔다. 관리형 CloudFront 캐시 정책 조회는 허용했다.
- Application Auto Scaling, CloudWatch 알람과 대시보드, SNS 권한은 observability 정책에 미리 넣었다.
- CloudTrail 목록만 믿지 않고 IAM Access Analyzer의 정책 생성으로 한 번 더 대조했다. 대조용 서비스 역할은 쓰고 나서 지웠다.

## 결과

- 좁힌 권한으로 처음 돌린 destroy가 EIP 연결 해제에서 멈췄다. 배포 역할 정책에 그 권한이 빠져 있었다. 권한을 넣고 다시 돌려 통과했다.
- Access Analyzer 대조에서도 하나가 더 나왔다. ALB를 만들 때 ELB가 배포 역할로 부르는 `ec2:GetSecurityGroupsForVpc`가 거부돼 있어서 정책에 추가했다. 대조 기간(2026-10-27 17:00 ~ 10-28 10:36)에 생성된 정책은 14개 서비스 179개 작업이었고, 허용했지만 쓰이지 않은 86개는 대부분 미리 넣은 권한과 변경 경로용 Modify, Update 작업이다.
- 나머지 경로는 처음부터 통과했다. bootstrap apply(2026-10-27)는 11 added, 1 destroyed로 역할에서 AdministratorAccess가 빠졌다. PR의 plan은 65 to add, 머지 뒤 자동 apply는 65 added로 끝났고 둘 다 AccessDenied 0건이었다. 배포 워크플로도 8분 만에 통과했다.
- 감수한 것: 코드를 읽고 보탠 작업은 실제로 돌려 보기 전까지 빠진 게 있을 수 있다. 이름 규칙(`3tier-prod-`)을 어기면 apply가 막힌다.
- 이후 ECS on EC2 전환과 관제 VPC 구성 때 `-compute-ec2`, `-network-e11` 정책을 더해 지금은 7개다.
