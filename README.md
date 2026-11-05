# 3-tier-terraform-ecs

**3계층 웹 서비스를 Terraform으로 구축하고, 장애 주입과 측정으로 가용성·관측성·비용을 개선한 기록입니다.**

Spring Boot 게시판(앱은 일부러 단순하게 두었습니다)을 AWS 3-Tier(ALB → ECS on EC2 → RDS)에 올리고, 배포 자동화·모니터링·중앙 로그·장애 실험·비용 최적화를 직접 만들었습니다. "구축했다"에서 멈추지 않고, 장애를 일부러 일으켜 **사용자 영향을 숫자로 재고 → 원인을 찾고 → 고치고 → 다시 재는** 순서로 진행했습니다.

![게시판 화면](docs/images/01-site.jpg)

## 핵심 결과

| 영역 | 결과 | 근거 |
|---|---|---|
| 재현성 | 리소스 148개를 **8분 51초**에 생성(접속 가능까지 9분 44초), **6분 51초**에 삭제. 모두 GitHub Actions에서 | [측정](docs/measurements.md), #50 |
| 배포 | PR 머지 1번 → 빌드 → 스테이징 → 승인 → 운영 롤링. 수동 명령 13개를 대체 | [측정](docs/measurements.md#배포-소요-시간-2026-10-28) |
| 롤백 | 기동 실패 이미지를 서킷 브레이커가 **5분 19초** 만에 되돌림. 그동안 응답 217회 모두 200 | [02](docs/troubleshooting/02-bad-image-rollback.md) |
| 가용성 | 태스크 1개 강제 종료 사용자 영향 **0초**, RDS Multi-AZ 장애 조치 영향 **약 44초** | [01](docs/troubleshooting/01-task-killed.md), [06](docs/troubleshooting/06-rds-failover.md) |
| Spot 회수 | FIS로 회수 예고를 보내며 개선을 반복해 요청 실패 **13 → 18 → 12 → 0건** | [비용 10절](docs/cost.md#10-spot-용량-공급자와-관측-토글-e09-46), [DEC-67](docs/adr/0067-spot-capacity-mix.md) |
| 탐지 | CPU 과부하 알림 Grafana **4분 10초** vs CloudWatch 6분 26초. 1분 남짓 전체 중단은 Grafana만 잡음(약 50초) | [관측 비교](docs/monitoring.md) |
| 원인 추적 | DB 차단 장애에서 로그에 원인 줄이 **10.7초** 만에 남고, 같은 요청 ID로 500 응답까지 연결 | [중앙 로그](docs/logging.md) |
| 비용 | 쓰지 않을 때 destroy로 월 195 → 22.79 USD(**−88%**). Spot으로 컴퓨트 −15%, 관측 서버를 끈 세션 −34% | [비용 리포트](docs/cost.md) |

## 아키텍처

```mermaid
flowchart LR
    U[사용자] -->|HTTPS 3tier.link| R53[Route 53]
    R53 --> ALB
    U -->|정적 파일| CF[CloudFront] -->|OAC| S3[(S3)]

    subgraph PROD["운영 VPC 10.0.0.0/16"]
        direction LR
        subgraph PUB["퍼블릭 (2a, 2c)"]
            ALB[ALB + ACM]
            NAT[리전 NAT]
        end
        subgraph PRIV["프라이빗 (2a, 2c)"]
            OD[EC2 온디맨드 2a<br/>태스크 1]
            SP[EC2 Spot 2c<br/>태스크 1 + 대기 1대]
        end
        subgraph DBS["DB 서브넷"]
            RDS[(RDS PostgreSQL)]
        end
    end

    subgraph MON["관제 VPC 10.100.0.0/16"]
        PG[Prometheus · Grafana]
        ELK[Elasticsearch · Kibana]
    end

    subgraph STG["스테이징 VPC 10.1.0.0/16 (필요할 때만)"]
        SALB[ALB] --> SEC[EC2 온디맨드 1대<br/>태스크 1] --> SRDS[(RDS)]
    end

    ALB --> OD & SP
    OD & SP --> RDS
    OD & SP -.->|FireLens 로그| ELK
    PG -.->|지표 수집| OD & SP
    PROD <-->|VPC 피어링| MON
    PG -->|알림| SNS[SNS] --> SL[Slack]
    CW[CloudWatch 비상 알람] --> SNS
```

| 계층 | 구성 | 선택 이유 |
|---|---|---|
| 진입 | Route 53, ACM, ALB, CloudFront + S3 | HTTPS 종료와 정적 파일 분리 |
| 앱 | ECS on EC2(t3.small), 용량 공급자 2개(온디맨드 base 1 + Spot), AZ별 ASG | 호스트 수준 관측과 태스크·인스턴스 2단계 스케일링 측정([DEC-36](docs/adr/0036-fargate-to-ecs-on-ec2.md)), Spot은 실패 0건 확인 후 채택([DEC-67](docs/adr/0067-spot-capacity-mix.md)) |
| 데이터 | RDS PostgreSQL, Secrets Manager | 외부 비공개, 비밀번호는 태스크에 주입. Multi-AZ는 장애 실험 때만 |
| 관제 | 별도 VPC의 Prometheus·Grafana, ELK, 피어링 | 운영과 장애 영역 분리([DEC-40](docs/adr/0040-three-vpcs-peering.md)). 관제가 죽어도 CloudWatch 비상 알람 2개는 남김 |
| 스테이징 | 운영과 같은 모듈을 작은 값으로 호출한 별도 루트(`terraform/staging`), 별도 VPC | 운영 배포 전 같은 이미지를 검증. 평소에는 내려 두고 배포 흐름 시험 때만 생성. 관제와는 아직 잇지 않아 스테이징은 Grafana·Kibana로 보지 않음 |
| 배포 | GitHub Actions + OIDC, ECR, 스테이징 → 운영 승인 배포 | 액세스 키 0개, 배포 역할은 서비스별 최소 권한([DEC-24](docs/adr/0024-deploy-role-least-privilege.md)) |

설계 근거(CIDR·SG·IAM·태그 규칙, 요청·배포·알람 흐름)는 [docs/architecture.md](docs/architecture.md)에 있습니다.

## 화면

| | |
|---|---|
| ![ECS 용량 공급자](docs/images/02-ecs-capacity-providers.jpg)<br/>온디맨드·Spot 용량 공급자와 AZ별 인스턴스 | ![대상 그룹](docs/images/03-target-group-healthy.jpg)<br/>ALB 대상 그룹 healthy |
| ![승인 배포](docs/images/04-deploy-approval.jpg)<br/>빌드 → 스테이징 → 운영 승인 대기 | ![부하 중 대시보드](docs/images/05-cloudwatch-dashboard-load.jpg)<br/>200 RPS 부하 중 대시보드 |
| ![스케일 아웃·인](docs/images/06-scale-out-in.jpg)<br/>태스크 2 → 4 → 2 | ![Slack 알람](docs/images/07-slack-alarm.jpg)<br/>5xx 비율 알람과 해소 |
| ![Kibana](docs/images/08-kibana-trace.jpg)<br/>요청 ID로 로그 추적 | |

## 장애 실험

모든 실험은 1초 간격 요청 기록([scripts/probe.ps1](scripts/probe.ps1))을 함께 돌려 사용자 영향을 쟀습니다.

| 실험 | 방법 | 사용자 영향 | 기록 |
|---|---|---|---|
| 태스크 강제 종료 | `ecs stop-task` 1개 / 2개 | 0초 / 46.5초 | [01](docs/troubleshooting/01-task-killed.md) |
| 잘못된 이미지 배포 | 기동 실패 이미지 머지 | 0건(자동 롤백 5분 19초) | [02](docs/troubleshooting/02-bad-image-rollback.md) |
| DB 연결 차단 | FIS 네트워크 차단 10분 | 약 10분(liveness는 정상, 재연결 1초 미만) | [03](docs/troubleshooting/03-db-connection-failure.md) |
| 컨테이너 인스턴스 종료 | ASG 인스턴스 종료 | 0초(관리형 드레이닝) | [04](docs/troubleshooting/04-instance-terminated.md) |
| RDS 장애 조치 | Multi-AZ 강제 장애 조치 | 약 44초 | [06](docs/troubleshooting/06-rds-failover.md) |
| Spot 회수 | FIS 회수 예고(2분) | 13건 → 개선 3번 → **0건** | [비용 10절](docs/cost.md#spot-회수-측정-aws-fis) |

실험 중 드러난 운영 문제도 같은 형식으로 남겼습니다(예: destroy 때 NAT가 먼저 지워져 서비스가 DRAINING에 멈춘 사고 [05](docs/troubleshooting/05-destroy-nat-order.md)).

## 실행 방법

1. `terraform/bootstrap`을 한 번 apply합니다(state 버킷, OIDC, 배포 역할, ECR, 호스팅 존). 값은 `terraform.tfvars.example`을 참고합니다.
2. 이후 인프라는 GitHub Actions로만 다룹니다.
   - `terraform/**`를 바꾼 PR: plan 결과가 코멘트로 달리고, 머지하면 운영에 apply됩니다.
   - 수동: Actions → `terraform` → `action=apply` 또는 `destroy`
   - 관측 서버 없이 띄우기: `enable_monitoring=false`, `enable_logging=false`
3. `app/**`를 바꾼 PR을 머지하면 이미지를 한 번 빌드해 스테이징 → (승인) → 운영 순서로 배포합니다.
4. 로컬 실행은 `docker compose up`(앱 + PostgreSQL). 앱 설명은 [app/README.md](app/README.md)에 있습니다.

## 폴더 구조

```
.
├── app/                  게시판 앱 (Spring Boot, Dockerfile)
├── docs/                 설계, 비용, 관측·로그 비교, 측정 상세, 장애 기록, ADR, 화면
├── load/                 k6 부하 시험
├── scripts/              장애 실험용 요청 기록(probe.ps1)
├── terraform/
│   ├── bootstrap/        최초 1회: state 버킷, OIDC, 배포 역할, ECR, Route 53, 예산, FIS 템플릿
│   ├── main/             운영: 반복 생성·삭제
│   ├── staging/          스테이징: 필요한 세션에만
│   └── modules/          network, data, compute, observability, monitoring, logging, vpc_peering
└── .github/workflows/    ci, deploy(스테이징 → 운영 승인), terraform, terraform-staging
```

## 문서

| 문서 | 내용 |
|---|---|
| [아키텍처 설계](docs/architecture.md) | CIDR·서브넷·SG·IAM·태그 규칙, 흐름도, 품질 목표치, 위험 |
| [측정 상세](docs/measurements.md) | 배포·롤백·부하·장애·EC2 전환 전후 측정표 |
| [비용 리포트](docs/cost.md) | 월 예상 비용, 실제 청구액, NAT 트레이드오프, Spot·관측 토글 |
| [관측 비교](docs/monitoring.md) | CloudWatch vs Prometheus·Grafana: 탐지 지연 실측, 비용 손익분기 |
| [중앙 로그](docs/logging.md) | 로그로 DB 장애 추적, ELK·Loki·CloudWatch Logs 비교 |
| [장애 기록](docs/troubleshooting/) | 증상 → 원인 → 조치 → 재발 방지 |
| [결정 기록(ADR)](docs/adr/) | 대표 결정 9건: 배경 → 선택지 → 결정 → 결과 |
| [프로젝트 히스토리 (Notion)](https://app.notion.com/p/3f4330bd3846812395f4d19208283e9c) | 에픽별 구축 기록, 결정 67건, 트러블슈팅, 실측 기록 DB |
| 작업 추적 | [Issues](https://github.com/DDongHyun00/3-tier-terraform-ecs/issues?q=is%3Aissue) · [Milestones](https://github.com/DDongHyun00/3-tier-terraform-ecs/milestones?state=closed) · [Project 보드](https://github.com/users/DDongHyun00/projects/11) |

## 진행 과정

| 에픽 | 내용 |
|---|---|
| E01~E02 | 앱 클라우드 대응(PostgreSQL, Flyway, 헬스체크, S3, 컨테이너), 설계 |
| E03~E05 | Terraform bootstrap, 네트워크·데이터, 컴퓨트·HTTPS |
| E06 | CI/CD(OIDC, 롤링 배포, plan 코멘트), 레포 보호 |
| E07~E08 | 오토스케일링·부하 시험, 장애 재현 |
| E10 | Fargate → ECS on EC2 전환과 전후 비교 |
| E11 | 관제 VPC, Prometheus·Grafana, 스테이징, 승인 배포 |
| E12 | 중앙 로그(구조화 로그, FireLens, Elasticsearch·Kibana) |
| E09 | 비용 분석(실제 청구액), Spot·관측 토글, 최종 재생성 측정 |
