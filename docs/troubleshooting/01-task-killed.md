# 장애 재현 ①: 태스크 강제 종료

ECS 태스크가 갑자기 멈췄을 때 ALB와 ECS가 어떻게 복구하는지, 사용자가 얼마나 영향을 받는지 쟀다(#41). 당시(2026-11-02, 스테이징 구축 전)는 환경이 운영 하나뿐이고 실사용자가 없는 데모라 운영에서 의도적으로 실험했다. 실무라면 스테이징에서 한다.

| 항목 | 1개 종료 | 2개 동시 종료 |
|---|---|---|
| 날짜 | 2026-11-02 00:45 KST | 2026-11-02 00:53 KST |
| 조건 | 태스크 2개(AZ마다 1개), Fargate 0.5 vCPU, probe 3개 URL 1초 간격 | 같음 |
| 사용자 영향 시간(probe 첫 실패 ~ 마지막 실패) | **0초** (1,248건 중 실패 0) | **46.5초** (1,635건 중 실패 140: 503 116, 502 24) |
| 용량 절반·0 구간(HealthyHostCount) | 00:45분 최솟값 1 | 00:53분 데이터 없음(타깃 0) |
| 멈춤 요청 → 정상 상태(steady state) | 76초 | 89초 |
| 울린 알람 | 없음 | 없음 (탐지 공백) |

## 재현 방법

조건:
- 서비스 `3tier-prod-board` 태스크 2개(AZ 2a·2c에 1개씩), 롤링 배포나 스케일링이 진행 중이 아닐 때
- 타깃 그룹 헬스체크 `/actuator/health/liveness`, 15초 간격, 정상 2회 / 비정상 2회, deregistration delay 30초
- 앱 graceful 종료 20초, 컨테이너 stopTimeout 30초

1. 사용자 쪽 응답 기록을 켠다. 1초마다 `GET /posts`를 보내고 시각·상태 코드·응답 시간을 CSV로 남긴다.

        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe.ps1 -Url https://3tier.link/posts

2. 태스크 1개를 멈춘다.

        aws ecs list-tasks --cluster 3tier-prod-cluster --service-name 3tier-prod-board --profile 3tier
        aws ecs stop-task --cluster 3tier-prod-cluster --task <태스크 ARN> --reason "E08-41 fault injection: stop 1 task" --profile 3tier

3. 2/2 healthy로 돌아오고 5분 뒤, 남은 태스크 2개를 동시에 멈춘다. 순서대로 실행하면 첫 호출이 늦어지는 동안 복구가 시작돼 "동시" 조건이 깨지므로, PowerShell 백그라운드 작업 두 개로 함께 시작하고 각 결과(태스크 ARN, 원하는 상태 STOPPED)를 확인한다.

        $arns = (aws ecs list-tasks --cluster 3tier-prod-cluster --service-name 3tier-prod-board --profile 3tier --query "taskArns" --output text) -split "\s+"
        $jobs = $arns | ForEach-Object { Start-Job -ArgumentList $_ -ScriptBlock { param($arn) aws ecs stop-task --cluster 3tier-prod-cluster --task $arn --reason "E08-41 fault injection: stop 2 tasks" --profile 3tier --query "task.[taskArn,desiredStatus,stoppedReason]" --output text } }
        $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job

4. 그동안 타깃 상태를 본다.

        aws elbv2 describe-target-health --target-group-arn <타깃 그룹 ARN> --profile 3tier --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]"

## 증상

### 예상 (실험 전)

`stop-task`는 컨테이너를 바로 죽이지 않는다. 로드 밸런서에 붙은 서비스 태스크는 멈추기 전에 DEACTIVATING 상태에서 타깃 그룹 등록 해제(draining)부터 한다([ECS 태스크 수명 주기](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle-explanation.html)). 그래서 ALB 헬스체크가 비정상을 판정할 일이 없을 것으로 예상했다.

1개 종료:

| 시점 | 일 | 근거 |
|---|---|---|
| t0 | 태스크 DEACTIVATING, 타깃 draining. ALB는 이 타깃에 새 요청을 보내지 않는다 | ECS 태스크 수명 주기 |
| t0 + 수 초 | 서비스 스케줄러가 실행 수 1 < 원하는 수 2를 보고 새 태스크를 시작한다 | |
| t0 + 30초 | deregistration delay가 끝나 SIGTERM, 앱 graceful 종료(최대 20초) 뒤 STOPPED | 타깃 그룹 설정, 앱 설정 |
| t0 + 약 30초 | 새 태스크가 타깃으로 등록된다(initial) | E07 실측: 시작 → 등록 29초 |
| t0 + 약 75초 | 헬스체크 2회 성공으로 healthy, 2/2 복귀 | E07 실측: 기동 75초 |

- 사용자 영향: 오류 0건. 약 75초 동안 용량만 절반이 된다.
- 알람: 비정상 타깃 알람은 울리지 않는다(draining은 비정상으로 세지 않는다). 5xx 비율 알람도 울리지 않는다.

2개 동시 종료:
- 두 타깃이 모두 draining이 되어 요청을 받을 타깃이 없다. 새 태스크가 healthy가 될 때까지 약 60~75초 동안 ALB가 503을 돌려줄 것으로 예상했다.
- 5xx 비율 알람(5% 초과, 5분 중 3분)은 중단이 1분 단위 구간 몇 개에 걸치느냐에 따라 울릴 수도, 안 울릴 수도 있다. 비정상 타깃 알람은 울리지 않는다.

### 실제 (2026-11-02 측정)

1개 종료 타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 00:45:20.4 | `stop-task` 요청, 응답 DEACTIVATING | CLI 출력 |
| 00:45:22.5 | 태스크 stoppingAt | describe-tasks |
| 00:45:49.0 | 타깃 등록 해제, draining 시작 (요청 후 약 29초) | ECS 서비스 이벤트 |
| 00:45:49.8 | 새 태스크 시작 | ECS 서비스 이벤트 |
| 00:46:17.7 | 새 타깃 등록 | ECS 서비스 이벤트 |
| 00:46:36.3 | steady state, 2/2 healthy | ECS 서비스 이벤트, 타깃 상태 |
| 00:46:46.6 | 멈춘 태스크 컨테이너 종료, 종료 코드 143(SIGTERM) | describe-tasks |

2개 동시 종료 타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 00:53:03.7 | 두 태스크 `stop-task` 병렬 요청 | CLI 출력 |
| 00:53:33.8 | 두 타깃 동시 등록 해제, draining 시작 (요청 후 약 30초) | ECS 서비스 이벤트 |
| 00:53:34.6 | probe 첫 실패(503) | probe CSV |
| 00:53:34.8 | 새 태스크 2개 시작 | ECS 서비스 이벤트 |
| 00:54:13.1 | 새 타깃 2개 등록 | ECS 서비스 이벤트 |
| 00:54:21.1 | probe 마지막 실패 | probe CSV |
| 00:54:32.5 | steady state, 2/2 healthy | ECS 서비스 이벤트 |
| 00:54:27~28 | 멈춘 두 태스크 컨테이너 종료, 종료 코드 143 | describe-tasks |

측정값:
- probe: 1개 종료 15:45~15:52 UTC 1,248건 실패 0. 2개 동시 종료 15:52:50~16:02 UTC 1,635건 중 실패 140(503 116, 502 24), 영향 46.5초.
- ALB(분 합계): 00:53 ELB 5xx 71 / 요청 106, 00:54 ELB 5xx 69(503 45, 502 24) / 요청 135. Target 5xx 데이터 없음(0). HealthyHostCount 최솟값 00:45 = 1, 00:53 = 데이터 없음. UnHealthyHostCount 최댓값 내내 0.
- 알람 이력: `3tier-prod-alb-5xx-rate`, `3tier-prod-alb-unhealthy-targets` 모두 StateUpdate 없음.

예상과 달랐던 것:
- `stop-task` 요청 뒤 등록 해제까지 두 번 모두 약 27~30초가 걸렸다. 예상은 "곧바로 draining"이었다. 그 30초 동안 멈추는 태스크가 계속 정상 응답해서 1개 종료의 사용자 영향은 여전히 0이었다. 이 지연은 아래 재발 방지 절에서 다룬다.
- 2개 동시 종료의 중단은 예상(60~75초)보다 짧은 46.5초였다. 등록 해제와 거의 동시에 새 태스크가 시작돼 기동(약 23초)과 헬스체크 2회가 중단 구간과 겹쳤기 때문이다.

캡처: 콘솔 캡처 대신 위 CLI 결과와 5초 간격 상태 기록(CSV)으로 남겼다.

## 측정 방법

사용자 체감(클라이언트)과 서버 지표를 함께 적는다.

- 클라이언트: `scripts/probe.ps1`의 CSV. 실패는 `ok` 열이 0인 요청(상태 코드가 200이 아니거나 curl 종료 코드가 0이 아님. 응답 헤더 200을 받은 뒤 본문 수신 중 시간 초과된 요청도 실패)이고, 영향 시간은 첫 실패부터 마지막 실패까지다. 실패가 없으면 0초다. 줄은 응답이 끝난 순서로 쌓이므로 `time_kst`(요청 시작 시각)로 정렬해서 본다.
- 서버: ALB 지표(1분 단위)와 ECS 서비스 이벤트(초 단위).

        aws ecs describe-services --cluster 3tier-prod-cluster --services 3tier-prod-board --profile 3tier --query "services[0].events[:15].[createdAt,message]"
        aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HealthyHostCount --dimensions Name=TargetGroup,Value=<targetgroup/...> Name=LoadBalancer,Value=<app/...> --statistics Minimum --period 60 --start-time <시작> --end-time <끝> --profile 3tier
        aws cloudwatch describe-alarm-history --alarm-name 3tier-prod-alb-5xx-rate --history-item-type StateUpdate --profile 3tier

  `UnHealthyHostCount`(Maximum)는 위와 같은 차원(TargetGroup + LoadBalancer)으로 조회한다. `HTTPCode_ELB_5XX_Count`·`HTTPCode_Target_5XX_Count`·`RequestCount`(Sum)는 알람과 같이 LoadBalancer 차원만으로 조회한다.

        aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_ELB_5XX_Count --dimensions Name=LoadBalancer,Value=<app/...> --statistics Sum --period 60 --start-time <시작> --end-time <끝> --profile 3tier

## 원인

- 1개 종료는 정상 종료 절차를 밟았다. 등록 해제(draining) 뒤 컨테이너가 종료 코드 143(SIGTERM)으로 끝났고, 그동안 다른 AZ의 태스크가 모든 요청을 받아 사용자 오류가 없었다.
- 2개 동시 종료는 두 타깃이 같은 시각(00:53:33.8)에 빠져 요청을 받을 타깃이 0이 됐다. ALB는 그동안 503을 돌려줬고, 새 타깃이 붙는 구간에서 502가 24건 났다. 중단 시간은 새 태스크 기동과 헬스체크 통과 시간과 맞는다.
- 알람이 울리지 않은 이유: 5xx 비율 알람은 1분 구간 5개 중 3개가 5%를 넘어야 하는데, 중단이 00:53·00:54 두 구간에만 걸쳤다. 비정상 타깃 알람은 타깃이 unhealthy가 아니라 등록 해제 상태였기 때문에 0으로 남았다.

## 해결

사람이 한 조치는 없다. ECS 서비스 스케줄러가 원하는 수(2)를 맞추려고 새 태스크를 띄우고, ALB가 헬스체크 2회 통과 뒤 트래픽을 보내 자동 복구됐다(1개 76초, 2개 89초).

## 재발 방지

지금 설정이 막는 것:
- 태스크를 AZ마다 1개씩 두어 하나가 멈춰도 다른 하나가 받는다(1개 종료 영향 0초).
- deregistration delay 30초와 앱 graceful 종료로 진행 중인 요청을 끝내고 멈춘다(종료 코드 143).

남은 위험과 제안(구현 안 함):
- 전체 중단이 1분 남짓이면 지금 알람으로는 탐지되지 않는다. `HealthyHostCount`가 1분 동안 1 미만이면 울리는 알람을 두면 짧은 전체 중단도 잡을 수 있다(SRE 목표 "장애 탐지 5분 이내" 기준). E11에서 Grafana AppNoScrapeTarget으로 약 50초 만에 탐지했다([monitoring.md](../monitoring.md)).
- `stop-task` 뒤 등록 해제까지 약 30초 지연의 원인을 확인하지 못했다. E10(EC2 전환) 재측정에서는 7초·6초로 짧아졌다(아래 재측정 절). Fargate 쪽에서만 나는 지연으로 좁혀졌지만 원인은 확인하지 못했다(범위 밖).

## 재측정 (2026-11-02 13:31·13:40 KST, ECS on EC2)

컴퓨트를 ECS on EC2(t3.small 2대, 인스턴스당 태스크 1개)로 바꾼 뒤(E10, #87) 같은 명령·같은 probe로 다시 쟀다(#89).

| 항목 | Fargate 1개 | EC2 1개 | Fargate 2개 동시 | EC2 2개 동시 |
|---|---|---|---|---|
| `stop-task` → 타깃 등록 해제 | 약 29초 | **7초** | 약 30초 | **6초** |
| 새 태스크 자리 대기(PROVISIONING) | 0 | 약 15~20초 | 0 | 약 11~13초 |
| 사용자 영향 시간 | 0초 (1,248건 중 0) | **0초** (478건 중 0) | 46.5초 (1,635건 중 140) | **68.8초** (598건 중 206: 503 170, 502 36) |
| 멈춤 요청 → steady state | 76초 | 85초 | 89초 | 81초 |
| 울린 알람 | 없음 | 없음 | 없음 | 없음 |

1개 종료 타임라인(KST): 13:31:07.8 `stop-task` → 13:31:14.8 타깃 등록 해제(7초) → 13:31:15.4 새 태스크 시작, 자리가 없어 PROVISIONING → 13:31:35 옛 태스크가 비운 자리에 PENDING(5초 간격 기록이라 13:31:30~35 사이) → 13:32:13.9 새 타깃 등록 → 13:32:33.1 steady state. 새 태스크는 옛 태스크가 쓰던 같은 인스턴스에 올라갔다.

2개 동시 종료 타임라인(KST): 13:40:09.0 병렬 `stop-task` → 13:40:15.4 두 타깃 동시 등록 해제(6초) → 13:40:16.1 새 태스크 2개 시작 → 13:40:16.8 probe 첫 실패(503) → 13:40:27 PENDING → 13:41:11.9 새 타깃 2개 등록 → 13:41:25.6 probe 마지막 실패(502) → 13:41:30.4 steady state.

달라진 점과 해석:
- 등록 해제가 30초에서 6~7초로 빨라졌다. 1개 종료에서는 차이가 없지만(어차피 영향 0), 2개 동시 종료에서는 Fargate 때 옛 태스크가 30초 더 응답해 주던 "덤"이 사라져 빈 구간이 바로 시작됐다.
- 인스턴스당 태스크 1개라 새 태스크가 옛 태스크의 자리를 기다렸다(약 11~20초, 5초 간격 상태 기록 기준). Fargate는 자리 개념이 없어 즉시 PENDING이었다.
- 두 요인이 겹쳐 2개 동시 종료의 사용자 영향이 46.5초에서 68.8초로 늘었다. 결론("태스크 2개가 동시에 죽으면 1분 남짓 503, 알람은 울리지 않음")은 같다.
- 원본 CSV는 레포에 넣지 않았다.
