# destroy 중 ECS 서비스가 멈춘 사고

실험으로 일으킨 장애와 달리 실제로 겪은 사고다. 컴퓨트를 ECS on EC2로 바꾼 날, 세션 끝에 돌린 `terraform destroy`가 처음으로 실패했다. 원인은 Terraform 의존 그래프에 없던 관계였다.

## 요약

2026-11-02 14:08~14:48 KST, destroy 중에 일어났다.

| 항목 | 값 |
|---|---|
| 증상 | destroy가 22분 22초 만에 오류 2개로 실패. 인스턴스, RDS, ALB, VPC가 남음 |
| 사용자 영향 | 없음 (서비스를 내리는 중) |
| 이상을 알아챈 시점 | 시작 12분 뒤 (Fargate 때 destroy는 5분 57초) |
| 끝난 뒤 정리까지 | 17분 |
| 추가 비용 | 리소스가 약 40분 더 떠 있었음, 약 0.1 USD |

같은 날 원인을 하나 고친 뒤 비슷한 사고가 한 번 더 났다. 두 번째는 실패를 끝까지 확인하지 않아 리소스가 약 20시간 더 떠 있었고 약 5 USD가 더 나갔다. 아래 "다시 일어난 일"에 적었다.

## 무슨 일이 있었나

GitHub Actions로 destroy를 실행했다. 82개를 지우는 계획이었는데 20분 넘게 걸리다가 두 오류로 끝났다.

    Error: waiting for ECS Service (.../3tier-prod-board) delete: timeout while waiting for state to become 'INACTIVE' (last state: 'DRAINING', timeout: 20m0s)
    Error: deleting EC2 Internet Gateway (igw-...): detaching ... from VPC (vpc-...): DependencyViolation: Network vpc-... has some mapped public address(es). Please unmap those public address(es) before detaching the gateway.

실행 중인 워크플로 로그는 끝나기 전에 읽을 수 없어서 AWS를 직접 조회했다.

- 14:20에 ECS 서비스는 DRAINING(태스크 0)이었고 ASG 2대, RDS, ALB, VPC는 그대로였다. NAT 2개는 이미 지워져 있었다.
- 멈춘 태스크를 조회하니 2개가 23분째 `STOPPING`이었다.

        aws ecs describe-tasks --cluster 3tier-prod-cluster --tasks <ARN...> --query "tasks[].[lastStatus,desiredStatus,stoppedAt]" --profile 3tier

- 컨테이너 인스턴스 2대 모두 `agentConnected`가 False였다.
- 시각을 맞춰 보니 서비스가 태스크를 멈춘 게 14:09:48, NAT가 지워진 게 14:09:56으로 8초 차이였다.

## 원인

Terraform이 지우는 순서 문제였다. ECS 서비스와 ASG는 사설 서브넷에는 의존하지만 NAT 게이트웨이나 사설 라우트에는 의존 관계가 없다. 그래서 destroy가 태스크 정지와 NAT 삭제를 동시에 시작했다.

NAT가 8초 만에 사라지자 사설 서브넷 인스턴스의 ECS 에이전트가 ECS 제어 플레인에 닿을 길이 없어졌다(VPC 엔드포인트도 없었다). 에이전트가 "태스크를 멈췄다"고 보고하지 못하니 태스크가 `STOPPING`에 묶였다. 태스크가 남아 있으면 서비스는 INACTIVE가 되지 않고([서비스 삭제 상태](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/delete-service-v2.html)), Terraform은 20분 뒤 포기한다. 서비스가 안 지워지니 타깃 그룹, 리스너, ALB도 남았다. ALB의 공인 IP가 VPC에 걸려 있어 인터넷 게이트웨이 분리도 실패했다. 두 번째 오류는 첫 오류의 결과다.

Fargate 때는 지우는 순서가 같아도 문제가 없었다. 태스크 정지를 Fargate 제어 플레인이 처리해서 VPC 안 에이전트 경로가 필요 없었기 때문이다. EC2로 바꾸면서 새로 생긴 의존 관계였다.

## 조치와 재발 방지

1. 컨테이너 인스턴스 2대를 강제로 등록 해제했다(14:35). 보고하지 못한 `STOPPING` 태스크가 `STOPPED`로 넘어갔다.

        aws ecs deregister-container-instance --cluster 3tier-prod-cluster --container-instance <ARN> --force --profile 3tier

2. 서비스가 INACTIVE가 된 걸 확인하고(14:37:51) destroy를 다시 돌렸다. 남은 35개를 5분 30초에 지웠고 프로젝트 리소스가 0인 걸 확인했다.

재발 방지로 network 모듈이 사설 서브넷의 인터넷 경로를 이루는 리소스(사설 기본 경로와 NAT, 사설 라우트 테이블 연결, 퍼블릭 기본 경로와 인터넷 게이트웨이, 퍼블릭 라우트 테이블 연결) ID를 내보내게 했다. compute 모듈은 이것을 `terraform_data.network_egress`로 묶고, ECS 서비스와 ASG가 여기에 `depends_on` 한다. 처음에는 NAT 경로만 넣었다가, 라우트 테이블 연결이나 퍼블릭 경로가 먼저 지워져도 같은 일이 날 수 있어서 경로 전체로 넓혔다. 이제 apply 때는 NAT 경로가 먼저 생기고, destroy 때는 서비스와 ASG가 끝난 뒤 NAT가 지워진다. 모듈 전체에 `depends_on`을 거는 방법은 쓰지 않았다. AMI 조회까지 apply 단계로 밀려 시작 템플릿에 매번 변경이 뜨기 때문이다. 이대로 두면 세션 끝 destroy가 매번 실패할 수 있어서 측정 세션 당일에 고쳤다.
## 다시 일어난 일

경로 의존을 넣고 다시 띄운 뒤, 같은 날 16:43에 돌린 destroy가 같은 증상으로 실패했다. 32개만 지우고 ECS 서비스가 DRAINING에서 20분 타임아웃이 났다.

- 이번에는 NAT와 사설 경로가 남아 있었다. 경로 의존은 제대로 동작했다.
- 지워진 32개 안에 컨테이너 인스턴스 역할의 ECS 정책 연결(`aws_iam_role_policy_attachment.ecs_instance_agent`)이 있었다. 서비스가 이 연결에 의존하지 않아 destroy가 둘을 함께 시작했고, 정책이 떨어진 순간 에이전트가 ECS를 부를 권한을 잃었다. 증상은 같았고 끊긴 게 네트워크에서 IAM 권한으로 바뀌었을 뿐이다.
- 같은 방법(강제 등록 해제, 서비스 INACTIVE 확인, destroy 재실행)으로 정리했다.
- 앱 서비스가 그 정책 연결에도 의존하게 했다. 데몬 서비스(node_exporter, cAdvisor)에도 같은 의존을 걸었다.

ECS 에이전트가 태스크 정지를 보고하려면 네트워크 경로, 인스턴스 역할 권한, 인스턴스 자체 세 가지가 필요하다. 서비스는 이 셋보다 먼저 지워져야 한다. 인스턴스(ASG)는 용량 공급자를 거쳐 이미 서비스 뒤에 지워지고 있었다.

이번 사고는 비용도 더 컸다. 실패한 destroy를 끝까지 확인하지 않고 세션을 마쳐서 RDS, ALB, NAT 2개, 인스턴스 2대가 다음 날 오후까지 약 20시간 더 떠 있었다(요금표 기준 약 5 USD). 그 뒤로 세션 끝 destroy는 끝날 때까지 지켜보고 리소스 0을 확인한다. 2026-11-05 마지막 destroy는 6분 51초에 끝났다([measurements.md](../measurements.md)).

## 배운 점과 개선 방향

배운 점:
- ECS 에이전트가 태스크 정지를 보고하려면 네트워크 경로, 인스턴스 역할 권한, 인스턴스 자체가 모두 살아 있어야 한다. 이 관계는 Terraform 그래프에 없어서 의존을 직접 걸어 줘야 했다. 명시적 의존(`depends_on`)은 생성 순서와 함께 삭제 순서도 정한다([Terraform 리소스 의존성](https://developer.hashicorp.com/terraform/tutorials/configuration-language/dependencies)).
- 한 원인을 고쳐도 같은 증상이 다른 경로로 다시 날 수 있었다. 처음에는 네트워크, 두 번째는 IAM 권한이었다. destroy는 끝까지 지켜보고 리소스 0을 확인해야 한다. 확인하지 않은 한 번에 약 5 USD가 더 나갔다.
- 에이전트가 NAT 없이 통신하게 하는 VPC 엔드포인트는 엔드포인트마다 시간당 약 0.01 USD에 가용 영역 수를 곱한 상시 비용이 들어서, 이 프로젝트에서는 NAT를 그대로 썼다([비용](../cost.md)).

개선 방향:
- 표준 구성은 ECS(`ecs`, `ecs-agent`, `ecs-telemetry`), ECR, CloudWatch Logs, Secrets Manager용 VPC 엔드포인트를 사설 서브넷에 두는 것이다. 그러면 NAT가 먼저 지워져도 에이전트가 ECS에 닿는다. AWS도 트래픽 대부분이 AWS 서비스로 간다면 엔드포인트를 쓰라고 권한다([NAT 게이트웨이 요금](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)).
- destroy 워크플로 끝에 프로젝트 태그가 붙은 리소스를 세어 0이 아니면 알리게 하면 사람이 확인하는 데 기대지 않아도 된다. 그 전까지는 destroy가 10분을 넘으면 `STOPPING` 태스크와 `agentConnected`부터 보면 된다.
