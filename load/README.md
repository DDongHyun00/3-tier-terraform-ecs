# 부하 시험 (k6)

ECS 서비스 오토스케일링(CPU 60% 목표, 태스크 2~4개)이 부하에 따라 늘고 주는지 확인하는 k6 스크립트다. 결과는 [측정 기록](../docs/measurements.md)에 있다.

## 1. 동작 방식

- 비로그인 GET만 보낸다. 목록 `/posts?page=0~9`와 상세 `/posts/1~99`를 3 : 7로 섞는다. 상세는 조회수를 올리므로 DB 쓰기도 섞인다.
- 실행기는 초당 요청 수를 고정하는 `ramping-arrival-rate`를 썼다. 응답이 느려져도 부하가 줄지 않아서 태스크가 늘어나야 버티는 상황이 된다.
- 가상 사용자가 쿠키를 유지한다(`noCookiesReset: true`). 상세 화면이 CSRF 토큰을 읽어 익명 요청에도 세션이 생기고, 세션은 RDS에 저장된다. 반복마다 쿠키를 지우면 요청마다 세션이 새로 생겨 실제 사용과 달라진다.
- 임계는 실패율 1% 미만, p95 1초 미만이다. 넘으면 k6가 실패로 끝나지만 측정값은 그대로 쓴다.

태스크 수는 목표 추적이 `현재 태스크 수 × CPU / 60`으로 정한다. 2개에서 평균 CPU가 90~100%면 3.0~3.3이 나와 4개까지 늘어난다.

늘림은 1분 지표가 3번 연속 60%를 넘을 때, 줄임은 15번 연속 54% 미만일 때 일어난다. 그래서 늘림은 부하 시작 후 3~4분, 줄임은 부하 종료 후 15~20분쯤으로 예상했다. 실제로는 늘림 결정까지 약 7분이 걸렸다([측정 기록](../docs/measurements.md)). 유지 구간이 5분이면 새 태스크가 부하를 나누기 전에 시험이 끝나서 10분으로 늘렸다.

## 2. 준비

k6를 설치한다.

    winget install GrafanaLabs.k6

## 3. 실행

1. 보정(약 4분). 30, 60, 120, 200 RPS를 1분씩 준다. ECS 서비스 CPU(CloudWatch `CPUUtilization` 또는 Grafana 앱 CPU)에서 태스크 2개 평균이 90%를 넘는 RPS를 찾는다.

        k6 run -e PROFILE=calibrate load/board.js

2. 본 시험(12분). 보정에서 찾은 RPS로 오르막 1분, 유지 10분, 내리막 1분을 준다. 전체 요약과 함께 요청마다 시각이 찍힌 원시 결과를 남긴다.

        k6 run -e PROFILE=main -e RATE=<RPS> --summary-export results/k6-summary.json --out csv=results/k6-main.csv load/board.js

3. 부하가 끝나면 태스크가 2개로 돌아올 때까지 기다린다.

다른 주소로 줄 때는 `-e BASE_URL=https://...`, 유지 시간을 바꿀 때는 `-e HOLD=15m`을 붙인다.

## 4. 결과 보는 법

| 항목 | 기준 |
|---|---|
| 스케일 아웃 시간 | 본 시험 시작부터 원하는 태스크 수가 바뀌고 새 타깃이 정상이 될 때까지 |
| 스케일 인 시간 | 부하 종료부터 원하는 태스크 수가 2로 돌아올 때까지 |
| p95 | 구간마다 클라이언트 값과 서버 값을 함께 본다 |
| 태스크당 처리량 | 보정에서 태스크 2개 평균 CPU가 90% 근처일 때의 RPS를 2로 나눈 값 |

p95의 클라이언트 값은 k6 `http_req_duration`, 서버 값은 ALB `TargetResponseTime`이다. 스케일 시각은 아래 명령과 타깃 그룹 상태로 확인한다.

    aws application-autoscaling describe-scaling-activities --service-namespace ecs --profile 3tier

### 구간별 p95

구간 경계는 스케일링 활동의 시작 시각(원하는 수 변경)과 새 타깃이 정상이 된 시각으로 잡는다. 경계가 둘이면 늘어나기 전, 새 태스크 기동 중, 늘어난 뒤 세 구간이 된다.

클라이언트(k6) 값은 원시 결과를 경계로 나눠 집계한다. 목록과 상세별로도 나온다.

    node load/p95.mjs results/k6-main.csv <경계1 ISO 시각> <경계2 ISO 시각>

형식 예시(2026-10-29 시험, 경계 셋):

    node load/p95.mjs results/k6-main.csv 2026-10-29T07:10:51Z 2026-10-29T07:12:11Z 2026-10-29T07:13:30Z

서버(ALB) 값은 구간마다 한 번씩 조회한다. 구간 길이를 `--period`로 주면 그 구간 전체의 p95가 하나 나온다. ALB 지표는 1분 단위라 시작과 끝을 분 경계에 맞추고 `--period`는 60의 배수로 준다.

    aws cloudwatch get-metric-statistics --profile 3tier --namespace AWS/ApplicationELB --metric-name TargetResponseTime --dimensions Name=LoadBalancer,Value=<ALB 차원> --start-time <구간 시작> --end-time <구간 끝> --period <구간 초> --extended-statistics p95

`<ALB 차원>`은 `aws elbv2 describe-load-balancers --names 3tier-prod-alb --profile 3tier`가 돌려주는 ARN에서 `app/`부터 끝까지다.

## 5. 한계

개인 프로젝트라 부하 발생용 인프라를 따로 두지 않고 집 PC(한국 가정망에서 서울 리전으로)에서 부하를 줬다.

- 클라이언트 p95에는 가정망 구간이 섞인다. 그래서 서버 처리 시간을 ALB `TargetResponseTime` p95로 따로 적었다. 두 백분위에 해당하는 요청이 서로 다를 수 있어서 차이가 곧 망 지연은 아니다.
- 부하를 주는 PC가 병목이면 결과가 무효다. 시험 중 PC CPU를 같이 보고 80%를 넘은 회차는 버리기로 했다([k6: 대규모 테스트 실행](https://grafana.com/docs/k6/latest/testing-guides/running-large-tests/)).
- 실무라면 같은 리전의 EC2나 Grafana Cloud k6에서 여러 지역으로 준다. 망 구간이 빠지고 같은 조건으로 반복하기 쉽다.
