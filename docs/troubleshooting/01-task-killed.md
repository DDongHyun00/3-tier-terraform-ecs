# 장애 재현 ①: 태스크 강제 종료

ECS 태스크가 갑자기 멈췄을 때 ALB와 ECS가 어떻게 복구하는지, 사용자가 얼마나 영향을 받는지 쟀다(#41). 환경이 운영(prod) 하나뿐이라 운영에서 의도적으로 실험했다. 실무라면 스테이징에서 한다.

| 항목 | 1개 종료 | 2개 동시 종료 |
|---|---|---|
| 날짜 | 세션에서 측정 | 세션에서 측정 |
| 조건 | 태스크 2개(AZ마다 1개), probe 1초 간격 | 같음 |
| 사용자 영향 시간(probe 첫 실패 ~ 마지막 실패) | 세션에서 측정 | 세션에서 측정 |
| 용량 절반·0 구간(HealthyHostCount) | 세션에서 측정 | 세션에서 측정 |
| 2/2 healthy 복귀까지 | 세션에서 측정 | 세션에서 측정 |
| 울린 알람 | 세션에서 측정 | 세션에서 측정 |

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

### 실제 (세션에서 측정)

타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 세션에서 측정 | | ECS 서비스 이벤트, 타깃 상태, probe CSV |

측정값:
- probe: 요청 수, 실패 수, 첫 실패·마지막 실패 시각 — 세션에서 측정
- ALB: `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`, `HealthyHostCount` 최솟값과 그 구간, `UnHealthyHostCount` 최댓값 — 세션에서 측정
- 알람 이력, Slack 도착 시각 — 세션에서 측정

캡처(Notion E08 에픽에 올린다): 장애 유발 명령 터미널, 타깃 그룹 draining·initial 순간 `E08-1-tg-draining.png`, 알람이 오면 Slack `E08-1-slack.png`, 복구 후 서비스 상태.

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

세션에서 측정한 뒤 쓴다. 확인할 것: 1개 종료가 정상 종료 절차(draining → SIGTERM)를 밟았는지, 2개 동시 종료의 중단 시간이 새 태스크 기동 시간과 맞는지.

## 해결

세션에서 측정한 뒤 쓴다. 자동 복구 경로: ECS 서비스 스케줄러가 원하는 수를 맞추려고 새 태스크를 띄우고, ALB가 헬스체크 통과 뒤 트래픽을 보낸다. 사람이 한 조치가 있으면 여기에 적는다.

## 재발 방지

세션에서 측정한 뒤 쓴다. 지금 설정이 막는 것(태스크 2개를 AZ에 나눠 둠, draining 30초, graceful 종료)과 남은 위험·제안(구현 안 함 표시)을 나눠 적는다.
