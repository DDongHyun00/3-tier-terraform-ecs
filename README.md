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
├── terraform/            (예정)
│   ├── bootstrap/        최초 1회 생성 후 유지: state 버킷, OIDC Provider, Route 53, ECR
│   └── main/             반복 생성·삭제: VPC, ALB, ECS, RDS, CloudWatch 등
└── .github/workflows/    (예정) 배포 파이프라인
```

앱 설명은 [app/README.md](app/README.md)에 있습니다.

## 진행 상태

- [x] 게시판 앱 준비
- [x] 클라우드 대응 리팩토링 (PostgreSQL 전환, Flyway, DB 세션 저장, 헬스체크, S3 파일 저장, 컨테이너 이미지)
- [ ] Terraform 인프라 구축
- [ ] CI/CD 파이프라인
- [ ] 모니터링과 오토스케일링
- [ ] 장애 재현과 기록
- [ ] 비용 정리
