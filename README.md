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

## 진행 상태

- [x] 게시판 앱 준비
- [x] 클라우드 대응 리팩토링 (PostgreSQL 전환, Flyway, DB 세션 저장, 헬스체크, S3 파일 저장, 컨테이너 이미지)
- [ ] Terraform 인프라 구축 (bootstrap, 네트워크·데이터 계층 완료 / 컴퓨트·HTTPS 진행 예정)
- [ ] CI/CD 파이프라인
- [ ] 모니터링과 오토스케일링
- [ ] 장애 재현과 기록
- [ ] 비용 정리
