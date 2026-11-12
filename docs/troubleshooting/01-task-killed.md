# 태스크 강제 종료

ECS 태스크가 갑자기 멈췄을 때 사용자가 얼마나 영향을 받고, ALB와 ECS가 어떻게 복구하는지 쟀다.

## 요약

2026-11-02에 태스크 2개(가용 영역마다 1개, Fargate 0.5 vCPU)로 쟀다.

당시에는 스테이징이 없었고 실사용자도 없는 데모라 운영 환경에서 실험했다. 실무라면 스테이징에서 할 실험이다.

| 항목 | 1개 종료 | 2개 동시 종료 |
|---|---|---|
| 사용자 영향 | 0초 (1,248건 중 실패 0) | 46.5초 (1,635건 중 실패 140) |
| 정상 복귀 | 76초 | 89초 |
| 울린 알람 | 없음 | 없음 |

## 재현

- 서비스 `3tier-prod-board` 태스크 2개, 배포나 스케일링이 진행 중이 아닐 때
- 타깃 그룹 헬스체크 `/actuator/health/liveness`, 15초 간격, 정상 2회와 비정상 2회, 등록 해제 지연 30초
- 앱 정상 종료 대기 20초, 컨테이너 `stopTimeout` 30초

1. 사용자 쪽 응답을 1초마다 기록한다.

        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe.ps1 -Url https://3tier.link/posts

2. 태스크 1개를 멈춘다.

        aws ecs list-tasks --cluster 3tier-prod-cluster --service-name 3tier-prod-board --profile 3tier
        aws ecs stop-task --cluster 3tier-prod-cluster --task <태스크 ARN> --reason "fault injection: stop 1 task" --profile 3tier

3. 2개가 다시 정상이 되고 5분 뒤 남은 2개를 동시에 멈춘다. 차례로 실행하면 첫 호출이 끝나기 전에 복구가 시작돼 "동시"가 깨진다. 그래서 PowerShell 백그라운드 작업 두 개로 같이 시작했다.

        $arns = (aws ecs list-tasks --cluster 3tier-prod-cluster --service-name 3tier-prod-board --profile 3tier --query "taskArns" --output text) -split "\s+"
        $jobs = $arns | ForEach-Object { Start-Job -ArgumentList $_ -ScriptBlock { param($arn) aws ecs stop-task --cluster 3tier-prod-cluster --task $arn --reason "fault injection: stop 2 tasks" --profile 3tier --query "task.[taskArn,desiredStatus]" --output text } }
        $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job

사용자 영향은 probe 기록에서 첫 실패부터 마지막 실패까지로 쟀다. 실패는 상태 코드가 200이 아니거나 연결이 실패한 요청이다.

## 무슨 일이 있었나

로드 밸런서에 붙은 태스크는 멈추기 전에 타깃 그룹에서 먼저 빠진다([ECS 태스크 수명 주기](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle-explanation.html)). 그래서 1개 종료는 오류 없이 지나가고, 2개 동시 종료는 새 태스크가 뜰 때까지 60~75초쯤 503이 날 거라고 예상했다.

1개 종료는 예상대로였다. 멈춘 태스크가 빠지는 동안 다른 가용 영역의 태스크가 요청을 다 받았고, 76초 만에 다시 2개가 됐다.

2개 동시 종료는 이렇게 흘러갔다.

| 시각 (KST) | 일 |
|---|---|
| 00:53:03 | 두 태스크 동시 종료 요청 |
| 00:53:33 | 두 타깃이 같이 빠짐 |
| 00:53:34 | 첫 503, 새 태스크 2개 시작 |
| 00:54:13 | 새 타깃 2개 등록 |
| 00:54:21 | 마지막 실패 |

예상과 달리 타깃은 바로 빠지지 않았다. 종료 요청부터 타깃 제외까지 두 번 모두 약 30초가 걸렸고, 그동안 멈추는 태스크가 정상 응답을 계속 보냈다. 중단은 오히려 예상보다 짧은 46.5초였다. 타깃이 빠지자마자 새 태스크가 시작돼 기동과 헬스체크가 중단 구간 안에서 같이 진행됐다.

## 원인

- 1개 종료는 정상 종료 절차를 밟았다. 타깃에서 빠진 뒤 컨테이너가 SIGTERM(종료 코드 143)으로 끝났다.
- 2개 동시 종료는 두 타깃이 같은 순간 빠져 요청을 받을 곳이 없어졌다. 실패 140건 가운데 116건은 ALB가 돌려준 503이었고, 나머지 24건은 새 타깃이 붙는 사이에 난 502였다.
- 알람은 둘 다 울리지 않았다. 5xx 비율 알람은 1분 구간 5개 중 3개가 5%를 넘어야 하는데 중단이 2개 구간에만 걸쳤다. 비정상 타깃 알람은 0으로 남았다. 등록 해제 중인 타깃은 비정상으로 세지 않는다.

## 조치와 재발 방지

사람이 한 조치는 없다. ECS가 원하는 태스크 수 2를 맞추려고 새 태스크를 띄웠고, 헬스체크를 통과하자 ALB가 다시 요청을 보냈다.

지금 설정의 보호 장치:
- 태스크를 가용 영역마다 1개씩 둬서 하나가 멈춰도 다른 하나가 받는다.
- 등록 해제 지연 30초와 앱 정상 종료로 처리 중인 요청을 끝내고 멈춘다.

1분 남짓한 전체 중단을 CloudWatch가 잡지 못한 문제는 Grafana에 "지표를 내는 앱 태스크 0개" 규칙을 넣어 메웠다. 같은 실험에서 약 50초 만에 Slack으로 알렸다([monitoring.md](../monitoring.md)).

## 다시 잰 결과 (ECS on EC2)

컴퓨트를 ECS on EC2(t3.small 2대, 인스턴스마다 태스크 1개)로 바꾼 뒤 같은 방법으로 다시 쟀다(2026-11-02).

| 항목 | Fargate (1개 / 2개) | ECS on EC2 (1개 / 2개) |
|---|---|---|
| 종료 요청부터 타깃 제외까지 | 약 29초 / 약 30초 | 7초 / 6초 |
| 새 태스크 자리 대기 | 없음 | 약 11~20초 |
| 사용자 영향 | 0초 (1,248건 중 0) / 46.5초 (1,635건 중 140) | 0초 (478건 중 0) / 68.8초 (598건 중 206) |
| 정상 복귀 | 76초 / 89초 | 85초 / 81초 |

- 타깃이 6~7초 만에 빠지면서, Fargate 때 옛 태스크가 30초 더 응답해 주던 여유가 사라졌다.
- 인스턴스마다 태스크가 1개라 새 태스크가 옛 태스크의 자리가 빌 때까지 기다렸다.
- 이 때문에 2개 동시 종료의 중단이 68.8초로 늘었다. 실패 206건은 503이 170건, 502가 36건이었다.
- 태스크 2개가 같이 죽으면 1분 남짓 503이 나고 CloudWatch 알람은 울리지 않는다. 이 결론은 Fargate 때와 같다.

## 배운 점과 개선 방향

배운 점:
- 태스크를 가용 영역마다 1개씩 두면 하나가 죽어도 사용자는 모른다. 둘이 같이 죽으면 1분 남짓 503이 난다.
- 1분 지표로 연속 조건을 보는 CloudWatch 알람은 1분 남짓한 전체 중단을 잡지 못한다.
- EC2에서는 타깃이 빨리 빠지는 대신 새 태스크가 옛 자리를 기다려서, 동시 종료 때 중단이 오히려 길어졌다. Fargate에서 종료 요청부터 타깃 제외까지 30초가 걸린 원인은 찾지 못했다.

개선 방향:
- CloudWatch에도 정상 타깃 수(`HealthyHostCount`)가 1 미만이면 울리는 알람을 두면 된다. 관제 서버가 죽어 있어도 짧은 전체 중단을 잡을 수 있다. 이 지표는 60초 단위로 나온다([ALB CloudWatch 지표](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html)).
- 두 태스크가 같이 죽어도 버티려면 인스턴스에 빈 자리를 하나 남겨 새 태스크가 옛 자리를 기다리지 않게 하는 게 맞다. Spot 쪽에 둔 대기 인스턴스와 같은 방식이다([Spot 회수](07-spot-interruption.md)).
