# 운영 사고: destroy 중 NAT가 먼저 지워져 ECS 서비스가 DRAINING에 고착

장애 재현이 아니라 실제로 겪은 사고다. ECS on EC2로 전환한 날(E10, #89 측정 뒤) 세션 끝에 돌린 `terraform destroy`가 처음으로 실패했다. 원인은 Terraform 그래프에 없던 의존 관계였다.

| 항목 | 값 |
|---|---|
| 날짜 | 2026-11-02 14:08~14:48 KST |
| 환경 | prod (destroy 중) |
| 증상 | destroy run이 22분 22초 만에 오류 2개로 실패. 인스턴스 2대·RDS·ALB·VPC가 남음 |
| 사용자 영향 | 없음 (서비스를 내리는 중) |
| 탐지까지 | 12분 (Fargate 때 destroy 5분 57초를 기준으로 "길다"고 느낀 시점). 실패 확정은 run 종료 |
| 해결까지 | run 종료 뒤 17분 (원인 확인 4분 → 인스턴스 강제 등록 해제 → 서비스 INACTIVE 2분 → destroy 재실행 5분 30초) |
| 비용 영향 | 인스턴스 2대·RDS·ALB가 약 40분 더 떠 있었다(약 0.1 USD) |

## 증상

run 41392316211(`gh workflow run terraform -f action=destroy`, 14:08:58)이 82개 삭제 계획을 세운 뒤 20분 넘게 걸리다가 두 오류로 끝났다.

    Error: waiting for ECS Service (.../3tier-prod-board) delete: timeout while waiting for state to become 'INACTIVE' (last state: 'DRAINING', timeout: 20m0s)
    Error: deleting EC2 Internet Gateway (igw-...): detaching ... from VPC (vpc-...): DependencyViolation: Network vpc-... has some mapped public address(es). Please unmap those public address(es) before detaching the gateway.

## 탐지

진행 중인 run의 로그는 끝나기 전에 읽을 수 없어서 AWS를 직접 조회했다.

- 14:20 ECS 서비스 DRAINING(태스크 0), ASG 2대·RDS·ALB·VPC 그대로. NAT 2개는 이미 deleted.
- 멈춘 태스크를 조회하니 2개가 23분 동안 `STOPPING`(stoppedAt 없음)이었다.

        aws ecs list-tasks --cluster 3tier-prod-cluster --desired-status STOPPED --profile 3tier
        aws ecs describe-tasks --cluster 3tier-prod-cluster --tasks <ARN...> --query "tasks[].[lastStatus,desiredStatus,stoppedAt]" --profile 3tier

- 컨테이너 인스턴스 2대의 `agentConnected`가 False.
- 시각을 맞춰 보니 서비스가 태스크 2개를 멈춘 시각 14:09:48, NAT DeleteTime 14:09:56. 8초 차이였다.

## 원인

Terraform destroy 순서다. ECS 서비스와 ASG는 사설 서브넷(관계 있음)에는 의존하지만 NAT 게이트웨이·사설 라우트에는 의존 관계가 없다. 그래서 destroy가 서비스 태스크 정지와 NAT 삭제를 동시에 시작했다. NAT가 8초 만에 사라지자 사설 서브넷 EC2 인스턴스의 ECS agent가 ECS 제어 플레인에 다다를 길이 없어져(VPC 엔드포인트 없음) "태스크를 정지했다"는 보고를 못 했다. 태스크가 STOPPING에 묶이면 서비스는 INACTIVE로 가지 않고([서비스 삭제 상태](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/delete-service-v2.html)), Terraform 제공자는 20분 뒤 포기한다. 서비스가 안 지워지니 타깃 그룹 → 리스너 → ALB도 남았고, ALB의 공인 IP가 VPC에 바늘된 상태라 IGW 분리가 DependencyViolation으로 실패했다. 두 번째 오류는 첫 오류의 결과다.

Fargate 때는 같은 destroy 순서였지만 태스크 정지를 Fargate 제어 플레인이 처리해 고객 VPC 쪽 agent 경로가 필요 없었다. EC2 전환으로 생긴 새 의존 관계다.

## 조치

1. 컨테이너 인스턴스 2대를 강제 등록 해제했다(14:35). agent가 보고하지 못한 STOPPING 태스크가 STOPPED로 넘어갔다.

        aws ecs deregister-container-instance --cluster 3tier-prod-cluster --container-instance <ARN> --force --profile 3tier

2. 서비스가 INACTIVE가 된 것을 확인하고(14:37:51) destroy를 다시 돌렸다. 남은 35개를 5분 30초에 지웠다(run 41395572307, 14:47:57). 프로젝트 리소스 0을 확인했다.

## 재발 방지

이 PR(#108)에서 한 것:
- 네트워크 모듈이 사설 서브넷의 기본 경로(`aws_route.private_nat`) ID를 출력하고, compute 모듈이 그것을 받아 `terraform_data.network_egress`에 묶은 뒤 ECS 서비스와 ASG가 그것에 `depends_on` 한다. apply 때는 NAT 경로가 먼저 만들어지고, destroy 때는 서비스·ASG가 끝난 뒤 NAT가 지워진다. 모듈 전체 `depends_on`은 AMI 데이터 소스까지 apply로 미뤄져 시작 템플릿에 매번 변경이 뜨므로 쓰지 않았다.
- 검증은 다음 AWS 세션에서 한다: apply 뒤 destroy 1회 성공, STOPPING 태스크 0, 소요 시간.

남긴 것:
- 표준 구성은 ECS(`ecs`, `ecs-agent`, `ecs-telemetry`)·ECR·CloudWatch Logs·Secrets Manager VPC 엔드포인트를 사설 서브넷에 두어 agent가 NAT 없이도 통신하게 하는 것이다. 엔드포인트당 시간당 약 0.01 USD × AZ의 상시 비용이 들어 E11 관제 VPC 설계에서 함께 결정한다.
- destroy가 10분을 넘으면 기다리지 말고 `STOPPING` 태스크와 `agentConnected`를 바로 본다. 세션 체크에 넣었다.

## 영향

사용자 영향은 없었다. 인스턴스 2대·RDS·ALB가 약 40분 더 떠 있었다(약 0.1 USD). 매 세션 끝 destroy가 이 구성에서는 반복 실패할 수 있었으므로, 측정 세션 당일에 고쳤다.
