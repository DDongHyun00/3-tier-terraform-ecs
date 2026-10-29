# 3-tier-terraform-ecs

Spring Boot 게시판 앱을 AWS 3-Tier 구조(ALB → ECS Fargate → RDS)에 Terraform으로 구축하고, 배포·모니터링·비용 관리까지 자동화하는 개인 프로젝트입니다.

> 진행 중입니다. 아래 내용 중 "예정"으로 표시한 부분은 아직 구현 전입니다.

## 아키텍처 (계획)

- 사용자 → Route 53 + ACM(HTTPS) → ALB(퍼블릭 서브넷) → ECS Fargate(프라이빗 서브넷, AZ 2곳) → RDS(DB 서브넷)
- 배포: GitHub Actions(OIDC 인증) → ECR → ECS 롤링 배포, 실패 시 자동 롤백
- 모니터링: CloudWatch 알람 → SNS → Amazon Q Developer in chat applications → Slack
- 보안: 액세스 키 없는 배포(OIDC), DB 비밀번호는 Secrets Manager로 주입, DB는 외부 비공개
- 비용: 리소스 태그 표준(Project / Env / Owner), AWS Budgets

## 폴더 구조

```
.
├── app/                  게시판 앱 (Spring Boot, Dockerfile 포함)
├── docker-compose.yml    로컬 확인용: 앱 + PostgreSQL
├── docs/                 아키텍처 설계 문서, 비용 리포트
├── load/                 k6 부하 테스트 스크립트 (오토스케일링 확인)
├── terraform/
│   ├── bootstrap/        최초 1회 생성 후 유지: state 버킷, OIDC Provider, Route 53, ECR
│   ├── main/             반복 생성·삭제: 모듈 호출, 변수, 출력 (terraform.tfvars.example 참고)
│   └── modules/          network(VPC·서브넷·NAT·SG), data(RDS·Secrets Manager·S3·CloudFront)
└── .github/workflows/    (예정) 배포 파이프라인
```

앱 설명은 [app/README.md](app/README.md)에 있습니다.

## 문서

- [아키텍처 설계](docs/architecture.md): CIDR·서브넷·SG·IAM·태그 규칙, 다이어그램
- [비용 리포트](docs/cost.md): 월 예상 비용, 최적화 전후, 항목별 절감 판단, NAT Gateway 트레이드오프
- [프로젝트 히스토리 (Notion)](https://app.notion.com/p/3f4330bd3846812395f4d19208283e9c): 에픽별 서사, 결정 기록(ADR), 트러블슈팅
- 작업 추적: [Issues](https://github.com/DDongHyun00/3-tier-terraform-ecs/issues) · [Milestones](https://github.com/DDongHyun00/3-tier-terraform-ecs/milestones) · [Project 보드](https://github.com/users/DDongHyun00/projects/11)

## 측정

### 배포 소요 시간 (2026-10-28)

main에 `app/**` 변경이 머지되면 GitHub Actions가 이미지를 빌드해 ECR에 올리고 ECS 서비스를 롤링 배포합니다(태스크 2개, 최소 100% / 최대 200%). 수동은 같은 단계(로컬 docker build → ECR push → 태스크 정의 등록 → 서비스 갱신 → 안정화 대기)를 명령 13개로 실행했습니다. E05 수동 배포 때는 빌드 시작 시각을 남기지 않아 전체 시간이 없어서, 같은 날 같은 단계를 다시 재서 비교했습니다.

| 구간 | 수동 | 자동 ① 캐시 적중 | 자동 ② 코드 변경 | 측정 방법 |
|---|---|---|---|---|
| 머지 → 러너 시작 | - | 9초 | 13초 | PR 머지 시각, 워크플로 타이머 시작 |
| 이미지 빌드·ECR push | 1분 56초 | 1분 31초 | 3분 58초 | 명령 시각 / 워크플로 Step Summary |
| ECS 롤링 (새 배포 → COMPLETED) | 3분 16초 | 3분 21초 | 3분 22초 | ECS 서비스 이벤트 |
| 시작 → 서비스 안정화 (ECS 기준) | 5분 18초 | 5분 5초 | 7분 38초 | ECS 서비스 이벤트 |
| 시작 → 워크플로 종료 (워크플로 기준) | - | 7분 18초 | 10분 16초 | 워크플로 실행 종료 시각 |
| 사람이 하는 일 | 명령 13개 | PR 머지 1번 | PR 머지 1번 | |

- 수동 값은 명령을 스크립트로 이어 실행한 최솟값입니다. 사람이 명령을 하나씩 입력하고 확인하는 시간은 들어 있지 않습니다.
- 자동 ①은 앱 코드가 이전 이미지와 같아 빌드 캐시가 모두 적중했고, ②는 Java 소스를 바꿔 다시 컴파일했습니다. ②의 빌드·push 3분 58초 중 2분 36초는 다음 빌드를 위한 GitHub Actions 캐시 내보내기(`cache-to: type=gha,mode=max`)이고, 이미지는 빌드 시작 1분 11초 만에 ECR에 올라갔습니다.
- 워크플로 종료가 ECS 기준보다 2~2.5분 늦습니다. 배포 액션이 서비스 안정화를 폴링하는 간격이 지수로 늘어나기 때문입니다(최소 15초, SDK 기본 최대 600초).
- 벽시계 시간은 수동 최솟값과 비슷하거나(①) 캐시 내보내기만큼 더 걸렸습니다(②). 자동화로 줄어든 것은 사람이 하는 일(명령 13개 → 머지 1번)과 그 사이 실수할 여지입니다.
- 근거: 자동 ① [run 40645647368](https://github.com/DDongHyun00/3-tier-terraform-ecs/actions/runs/40645647368), ② [run 40646991446](https://github.com/DDongHyun00/3-tier-terraform-ecs/actions/runs/40646991446)

### 롤백 소요 시간 (서킷 브레이커, 2026-10-28)

환경이 하나라 운영(prod)에서 의도적으로 실험했습니다. 실무라면 스테이징에서 합니다.

기동에 실패하는 이미지를 배포했습니다. 앱이 읽는 버킷 환경 변수 이름을 `ASSETS_BUCKET`으로 바꿨고 태스크 정의는 그대로 `S3_BUCKET`을 넣습니다. 테스트는 로컬 저장소를 써서 CI는 통과하고, 운영에서만 기동 중 예외로 종료됩니다([#67](https://github.com/DDongHyun00/3-tier-terraform-ecs/pull/67), 되돌림 [#68](https://github.com/DDongHyun00/3-tier-terraform-ecs/pull/68)).

| 구간 | 시간 | 측정 방법 |
|---|---|---|
| 실패 배포 시작 → 실패 판정 | 4분 5초 | ECS 이벤트 `deployment failed: tasks failed to start` |
| 실패 판정 → 이전 리비전 COMPLETED | 1분 14초 | ECS 이벤트 `rolling back to deployment` → `deployment completed` |
| 롤백 전체 (실패 배포 시작 → 이전 리비전 복귀) | 5분 19초 | ECS 서비스 이벤트 |
| 머지 → 이전 리비전 복귀 | 7분 44초 | PR 머지 시각, ECS 서비스 이벤트 |
| 워크플로가 실패를 알린 시각 | 복귀 8분 33초 뒤 | 워크플로 로그 |
| 롤백 중 사이트 응답 | 217회 중 217회 200 | liveness 5초 간격 |

- 새 태스크 5개가 모두 기동 중 종료됐고, 실패 수가 서킷 브레이커 임계값 3(원하는 태스크 수 × 50%, 최소 3)에 닿자 직전 배포로 되돌렸습니다.
- 최소 정상 비율이 100%라 기존 태스크 2개가 그동안 계속 트래픽을 받았습니다.
- 워크플로 알림이 늦은 이유는 위의 폴링 간격입니다. 오래 기다린 배포일수록 간격이 길어집니다.
- 근거: [run 40643279590](https://github.com/DDongHyun00/3-tier-terraform-ecs/actions/runs/40643279590)

## 진행 상태

- [x] 게시판 앱 준비
- [x] 클라우드 대응 리팩토링 (PostgreSQL 전환, Flyway, DB 세션 저장, 헬스체크, S3 파일 저장, 컨테이너 이미지)
- [ ] Terraform 인프라 구축 (bootstrap, 네트워크·데이터 계층 완료 / 컴퓨트·HTTPS 진행 예정)
- [ ] CI/CD 파이프라인
- [ ] 모니터링과 오토스케일링
- [ ] 장애 재현과 기록
- [ ] 비용 정리
