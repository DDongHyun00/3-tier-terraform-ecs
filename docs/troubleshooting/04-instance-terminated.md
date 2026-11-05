# 장애 재현 ④: 컨테이너 인스턴스 1대 종료 (ECS on EC2)

컴퓨트를 Fargate에서 ECS on EC2로 바꾼 뒤(E10, #87) 생긴 새 장애 지점을 재현했다. 태스크가 올라가 있는 EC2 인스턴스 1대를 ASG를 통해 종료해, 그 위의 태스크가 어디로 옮겨 가고 사용자가 얼마나 영향을 받는지 쟀다(#89). Fargate에서는 호스트가 보이지 않아 이 시나리오 자체가 없었다. 당시(2026-11-02, 스테이징 구축 전)는 환경이 운영 하나뿐이고 실사용자가 없는 데모라 운영에서 의도적으로 실험했다. 실무라면 스테이징에서 한다.

| 항목 | 값 |
|---|---|
| 날짜 | 2026-11-02 13:44 KST |
| 환경 | prod (당시는 스테이징 구축 전이라 환경이 운영 하나뿐이고 실사용자가 없는 데모여서 운영에서 의도적으로 실험. 실무라면 스테이징) |
| 조건 | t3.small 2대(AZ 2a·2c), 인스턴스당 태스크 1개, 용량 공급자 관리형 종료 보호·관리형 드레이닝 켜짐, probe 3개 URL 1초 간격 |
| 종료 방법 | `terminate-instance-in-auto-scaling-group`, desired 유지(ASG가 대체 인스턴스를 띄움) |
| 사용자 영향 시간 | **0초, ALB 지표 기준** (13:44~13:48 ELB 5xx·Target 5xx·타깃 연결 오류 모두 0). probe는 요청 46초 뒤부터 기록해 첫 46초의 클라이언트 관측이 없고, 13:47의 타임아웃 21건은 원인을 확인하지 못해 영향 시간에서 뺀 채 따로 적었다 |
| 새 태스크 healthy까지 | **88초** (요청 13:44:10 → 타깃 등록 13:45:38) |
| 대체 인스턴스 클러스터 등록까지 | 47초 이내 (13:44:57 조회 때 이미 ACTIVE) |
| 옛 인스턴스 종료 완료까지 | 4분 30초 (13:48:40) |
| 울린 알람 | 없음 (타깃이 unhealthy가 된 적이 없음) |

## 재현 방법

조건:
- 서비스 `3tier-prod-board` 태스크 2개(AZ 2a·2c에 1개씩), 인스턴스 2대, 롤링 배포나 스케일링이 진행 중이 아닐 때
- 용량 공급자 `3tier-prod-ec2`: 관리형 종료 보호 ENABLED, 관리형 드레이닝 ENABLED(ASG 종료 수명주기 훅을 ECS가 받는다)
- 타깃 그룹 헬스체크 `/actuator/health/liveness`, 15초 간격, 정상 2회 / 비정상 2회, deregistration delay 30초

1. 사용자 쪽 응답 기록과 5초 간격 상태 기록을 켠다. 상태 기록은 타깃 상태별 수, 서비스 desired/running/pending, 태스크별 lastStatus, 컨테이너 인스턴스 ACTIVE/DRAINING 수, ASG desired/InService를 한 줄로 남긴다.

        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe.ps1 -Url https://3tier.link/posts,https://3tier.link/actuator/health,https://3tier.link/actuator/health/liveness -IntervalSeconds 1 -MaxTimeSeconds 600 -OutFile <경로>

2. 종료할 인스턴스를 고른다(여기서는 2a).

        aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names 3tier-prod-ecs-asg --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone]" --profile 3tier

3. ASG를 통해 종료한다. `--no-should-decrement-desired-capacity`라서 ASG는 대체 인스턴스를 띄운다.

        aws autoscaling terminate-instance-in-auto-scaling-group --instance-id <인스턴스 ID> --no-should-decrement-desired-capacity --profile 3tier

4. 그동안 컨테이너 인스턴스 상태(DRAINING 전환), 서비스 이벤트, ASG 활동을 본다.

        aws ecs describe-container-instances --cluster 3tier-prod-cluster --container-instances <ARN...> --query "containerInstances[].[ec2InstanceId,status,runningTasksCount]" --profile 3tier
        aws autoscaling describe-scaling-activities --auto-scaling-group-name 3tier-prod-ecs-asg --max-items 3 --profile 3tier

## 예상 동작

인스턴스가 바로 꺼지는 하드웨어 장애를 가정했다.
- 그 위의 태스크가 즉시 죽고, ALB 헬스체크(15초 간격·2회 실패)가 죽은 타깃을 떼기까지 30~40초 동안 요청 절반이 502·504로 실패한다.
- ECS가 새 태스크를 만들지만 남은 인스턴스는 꽉 차 있어(1개/대) 대체 인스턴스가 기동·등록될 때까지 PROVISIONING으로 기다린다. 기동·등록 약 90초 + 앱 기동 약 60초로 복귀 3분 안팎.
- 알람: 비정상 타깃 알람(unhealthy ≥ 1, 1분)이 울릴 가능성이 있다.

## 증상 (실제, 2026-11-02 측정)

타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 13:44:10.7 | ASG 종료 요청 수신, 상태 `MidTerminatingLifecycleAction`(수명주기 훅에서 대기) | ASG 활동 |
| 13:44:16 | ASG가 대체 인스턴스 기동 시작(desired 2 유지, 실제 1→2) | ASG 활동 |
| 13:44:34.6 | 서비스가 새 태스크 1개 생성(PROVISIONING) | ECS 서비스 이벤트 |
| 13:44:57 | 옛 인스턴스 DRAINING, 그 위 태스크는 RUNNING·healthy 유지. 대체 인스턴스는 이미 ACTIVE(태스크 0) | describe-container-instances, 타깃 상태 |
| 13:45:08.2 | 새 태스크가 대체 인스턴스에서 기동 | ECS 서비스 이벤트 |
| 13:45:38.7 | 새 타깃 등록, healthy 3개 | ECS 서비스 이벤트, 상태 기록 |
| 13:46:36.7 | 옛 태스크 정지 | ECS 서비스 이벤트 |
| 13:46:46.7 | 옛 타깃 등록 해제, 드레이닝, steady state | ECS 서비스 이벤트 |
| 13:48:40 | 옛 인스턴스 종료 완료 | ASG 활동 |

측정값:
- probe: 13:44:56~13:53 649건(종료 요청 46초 뒤부터. 기록을 시작하기 전에 종료 명령을 실행해 처음 46초는 클라이언트 관측이 없다). HTTP 오류 0건. 13:47:14~13:47:36에 요청 시작된 21건이 21초 타임아웃(코드 000, curl 28)으로 실패했다(아래 참고).
- ALB(분 합계): 13:44~13:47 `HTTPCode_ELB_5XX_Count`·`HTTPCode_Target_5XX_Count`·`TargetConnectionErrorCount` 모두 데이터 없음(0). `RequestCount` 13:45 357, 13:46 336, 13:47 338으로 일정했다.
- 타깃 상태: healthy가 2 → 3 → 2로 움직였고 unhealthy는 내내 0.
- 알람 이력: StateUpdate 없음.

예상과 달랐던 것:
- 즉시 정지가 아니라 **우아한 교체**였다. 용량 공급자의 관리형 드레이닝이 ASG 종료 수명주기 훅을 받아 인스턴스를 DRAINING으로 바꾸고, 새 태스크가 healthy가 된 뒤에야 옛 태스크를 내리고 인스턴스를 꺼서 사용자 영향이 0이었다. 예상한 30~40초 실패 구간은 생기지 않았다.
- 대체 인스턴스가 47초 안에 클러스터에 등록됐다. 설계 때 예상(90초)보다 빨랐고, 12:40 스케일 아웃 때 52초와 비슷하다.
- probe 타임아웃 21건의 원인은 확인하지 못했다(범위 밖). 서버 쪽 지표(ELB·Target 5xx, 타깃 연결 오류)가 0이고 같은 초의 다른 요청이 정상 응답했으며 분 단위 `RequestCount`가 늘지 않아 클라이언트 쪽 네트워크를 의심하지만, 분 단위 합계로는 요청 21건의 도달 여부를 가릴 수 없다. 그래서 영향 시간은 "ALB 지표 기준 0초"로 한정해 적고 이 21건은 따로 남겼다. 새 태스크 healthy(13:45:38)와 옛 태스크 정지(13:46:36) 어느 전환 시각과도 겹치지 않는다.

## 측정 방법

- 클라이언트: `scripts/probe.ps1`의 CSV. 실패 판정과 영향 시간 계산은 [01-task-killed.md](01-task-killed.md) "측정 방법"과 같다. 코드 000·curl 28(타임아웃)은 ALB `RequestCount`와 대조해 도달 여부를 가른다.
- 서버: ECS 서비스 이벤트(초 단위), 컨테이너 인스턴스 상태, ASG 활동(`describe-scaling-activities`), ALB 지표(1분 단위).
- 상태 기록: 5초 간격으로 `describe-target-health`, `describe-services`, `describe-tasks`, `describe-container-instances`, `describe-auto-scaling-groups`를 묶어 CSV 한 줄로 남겼다.

## 원인

사용자 영향이 0이었던 이유는 두 설정이 맞물렸기 때문이다.
- **관리형 드레이닝**: 용량 공급자가 ASG에 종료 수명주기 훅을 걸어 두고, 종료 요청이 오면 ECS가 그 인스턴스를 DRAINING으로 바꾼다. DRAINING 인스턴스의 서비스 태스크는 다른 곳에 대체 태스크가 떠서 healthy가 될 때까지 계속 요청을 받는다([관리형 인스턴스 드레이닝](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/managed-instance-draining.html)).
- **desired 유지**: `--no-should-decrement-desired-capacity`라 ASG가 곧바로 대체 인스턴스를 띄웠고, 인스턴스당 태스크 1개라 꽉 찬 클러스터에서도 새 태스크를 놓을 자리가 47초 만에 생겼다.

이 경로는 "ASG가 종료를 주관하는 경우"(스케일 인, 인스턴스 새로 고침, 수동 ASG 종료)다. 전원이 바로 꺼지는 하드웨어 장애나 `ec2 terminate-instances`로 직접 끄는 경우는 훅을 거치지 않아 예상 동작(30~40초 실패)이 그대로 나올 것으로 본다. 그 경로는 아직 재지 않았다.

## 해결

사람이 한 조치는 없다. ECS(드레이닝·태스크 교체)와 ASG(대체 인스턴스)가 자동으로 처리했고, 교체가 끝나는 데 4분 30초가 걸렸다.

## 재발 방지

지금 설정이 막는 것:
- 관리형 종료 보호 + 관리형 드레이닝으로 ASG가 주관하는 모든 종료(스케일 인 포함)에서 태스크가 있는 인스턴스는 보호되거나 비운 뒤 꺼진다. 같은 날 스케일 인(4→2)에서도 태스크 있는 2대는 남고 빈 2대만 종료됐다.
- 태스크를 AZ마다 1개씩 두고 ASG 상한을 태스크 상한의 2배(8)로 둬서 교체·배포 때 새 태스크를 놓을 인스턴스가 늘 생긴다.

남은 위험과 제안(구현 안 함):
- 훅을 거치지 않는 즉시 정지(하드웨어 장애, `ec2 terminate-instances`)는 측정하지 않았다. 다음 측정 세션 후보다. 그 경우 영향은 헬스체크 간격·실패 횟수(15초·2회)에 달려 있어, 더 줄이려면 간격을 10초로 당기는 대가(헬스체크 요청 증가)를 따져야 한다.
- 대체 인스턴스가 뜰 때까지 용량이 절반이다. 부하 중이라면 짧게는 CPU 알람, 길게는 스케일 아웃이 겹친다. 여유 용량(용량 공급자 목표 80%)은 상시 비용이 들어 이때는 두지 않았다. 이후 E09에서 Spot 용량 공급자에만 목표 50%로 대기 1대를 두었다([cost.md](../cost.md) 10절).
