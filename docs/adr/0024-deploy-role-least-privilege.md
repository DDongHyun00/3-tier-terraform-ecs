# DEC-24. 배포 역할을 서비스별 정책 5개와 permissions boundary로 좁혔다

- 상태: 확정 · 날짜: 2026-10-27 · 검증: 실측 완료
- 관련 이슈: https://github.com/DDongHyun00/3-tier-terraform-ecs/issues/35

## 배경

E03에서 GitHub OIDC 배포 역할 `3tier-github-deploy`를 AdministratorAccess로 열어 두고, 실제 호출 기록을 보고 E06에서 좁히기로 했다(E03 결정 기록). CloudTrail 이벤트 기록을 조회해 보니 이 역할 세션은 ci.yml의 plan만 돌려서 읽기 작업 67개밖에 남기지 않았다. 그래서 쓰기 작업 84개는 같은 Terraform 코드를 로컬 SSO로 apply·destroy한 10/20~10/23 이벤트에서 가져왔다. S3 객체, ECR 레이어, PassRole, 태그처럼 이벤트 기록에 안 남는 작업은 코드를 읽고 보충했다. 이렇게 모은 151개 작업을 서비스 14개로 나눠 정책을 썼다.

## 결정 요인

- 설계 요구사항: IAM 최소 권한
- 배포 역할은 IAM 역할을 만들고 정책을 붙일 수 있어야 한다. 이 권한이 넓으면 역할이 스스로 권한을 키울 수 있다
- E07(오토스케일링, 알람, 대시보드)이 곧 같은 역할로 apply된다

## 검토한 선택지

- IAM·PassRole 리소스 범위 `3tier-*`: bootstrap 쪽 이름까지 한 패턴으로 묶여 편했지만, 배포 역할 자신과 그 정책도 걸려 역할이 자기 정책을 고쳐 AdministratorAccess와 같은 상태로 돌아갈 수 있었다. 그래서 되돌렸다.
- 리소스 범위 `3tier-prod-*` + 명시적 Deny: main 스택이 만드는 역할·정책은 전부 `3tier-prod-` 접두사라 이것으로 충분했다. 자기 역할, 자기 정책 5개, permissions boundary 정책 수정을 명시적 Deny로 한 번 더 막았다.
- ECS 역할 쪽 상승 경로: `3tier-prod-*` 역할에 PutRolePolicy로 아무 인라인 정책이나 붙인 뒤 그 역할을 넘겨 받으면 권한이 커진다. 리소스 범위로는 못 막아, ECS 역할 생성·수정 시 permissions boundary `3tier-ecs-boundary`를 조건으로 강제했다.
- E07 권한을 그때 추가 vs 지금 선반영: 그때 추가하면 E07 첫 apply가 AccessDenied로 실패하고 bootstrap을 다시 apply해야 한다. Application Auto Scaling, CloudWatch 알람·대시보드, SNS 권한을 observability 정책에 미리 넣었다.
- 검증 방법: CloudTrail 목록만 믿을지, IAM Access Analyzer 정책 생성으로 교차 검증할지. 일회성 서비스 역할 `AccessAnalyzerMonitorServiceRole-3tier`를 만들어 비교한 뒤 지우기로 했다.

## 결정

- AdministratorAccess를 떼고 서비스별 고객 관리형 정책 5개를 붙였다: `3tier-github-deploy-state-ecr`, `-network`, `-compute`, `-data`, `-observability`.
- IAM 작업과 PassRole은 `3tier-prod-*`로 한정하고, 자기 역할·자기 정책·boundary 수정은 명시적 Deny.
- ECS 역할은 permissions boundary `3tier-ecs-boundary` 아래에서만 만들고 고칠 수 있게 했다.
- EC2·ACM·CloudFront는 ARN 범위를 좁혔고, 관리형 CloudFront 캐시 정책 조회는 허용했다.
- E07 권한은 선반영했다.

## 결과

- bootstrap apply(10/27): 11 added, 1 destroyed. 역할에 AdministratorAccess가 없다.
- CI run 40473975684에서 새 권한으로 terraform-plan이 65 to add로 통과했다. AccessDenied 0건.
- 쓰기 경로 검증(10/28): PR #63 머지 뒤 자동 apply run 40516746323이 65 added, AccessDenied 0건. deploy 수동 run 40609837109도 8분 만에 통과. destroy는 첫 실행 run 40610805192가 EIP 연결 해제에서 멈췄다. 배포 역할에 EIP 연결 해제 권한이 빠져 있었고, PR #64로 넣은 뒤 run 40615951435에서 통과했다.
- Access Analyzer 대조(10/27 17:00~10/28 10:36): 생성된 정책은 14개 서비스 179개 작업. 실제로 거부된 작업은 ALB 생성 때 ELB가 배포 역할로 부르는 `ec2:GetSecurityGroupsForVpc` 1개였고, PR #64(aa7eafa)로 추가했다. 허용했지만 관측되지 않은 작업 86개는 대부분 E07 선반영분과 변경 경로용 Modify/Update다.
- 10/28 PR #64 머지 후 bootstrap apply로 반영을 확인했고, 대조용 서비스 역할은 삭제했다(조회 시 NoSuchEntity).
- 감수한 것: 코드에서 보충한 작업은 실제로 돌려 보기 전까지 빠진 게 있을 수 있다. E07 권한은 미리 연 것이다. 이름 규칙(`3tier-prod-`)을 어기면 apply가 막힌다.
- 이후 ECS on EC2 전환(E10)과 관제 VPC(E11)에서 `-compute-ec2`, `-network-e11` 정책을 더해 지금은 7개다.
- [PR #63](https://github.com/DDongHyun00/3-tier-terraform-ecs/pull/63), [PR #64](https://github.com/DDongHyun00/3-tier-terraform-ecs/pull/64)
