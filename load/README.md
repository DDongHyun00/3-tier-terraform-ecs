# 부하 테스트 (k6)

ECS 서비스 오토스케일링(서비스 평균 CPU 60% 목표 추적, 태스크 2~4개)이 부하에 따라 늘고 주는지 확인하려고 만든 스크립트다(#40). 결과 수치는 루트 README `## 측정`에 적는다.

## 시나리오

- 비로그인 GET만 썼다. 목록 `/posts?page=0~9` 3 : 상세 `/posts/1~99` 7. 상세는 조회수를 올리므로(UPDATE) DB 쓰기도 섞인다.
- 실행기는 초당 요청 수를 고정하는 `ramping-arrival-rate`로 골랐다. 응답이 느려져도 부하가 줄지 않아서 "태스크가 늘어나야 버티는" 상황이 된다.
- 가상 사용자가 쿠키를 유지하게 했다(`noCookiesReset: true`). 상세 화면이 CSRF 토큰을 읽어 익명 요청에도 세션이 생기고 세션은 RDS에 저장된다. 쿠키를 반복마다 지우면 요청마다 세션 INSERT가 생겨 실제 사용 패턴과 달라진다.
- 임계는 실패율 1% 미만, p95 1초 미만(전체·목록·상세)으로 두었다. 넘으면 k6가 실패로 끝나지만 측정은 그대로 쓴다.

## 실행

k6 설치: `winget install GrafanaLabs.k6`

1. 보정(약 4분): 30 → 60 → 120 → 200 RPS를 1분씩 준다. 대시보드 ECS CPU에서 태스크 2개 평균이 90%를 넘는 RPS를 찾는다.

        k6 run -e PROFILE=calibrate load/board.js

2. 본 시험(12분): 보정에서 찾은 RPS로 오르막 1분, 유지 10분, 내리막 1분. 전체 요약(`--summary-export`)과 함께 요청마다 시각이 찍힌 원시 결과(`--out csv`)를 남긴다. 구간별 p95는 원시 결과로 다시 집계한다.

        k6 run -e PROFILE=main -e RATE=<RPS> --summary-export local/captures/E7/k6-summary.json --out csv=local/captures/E7/k6-main.csv load/board.js

   - 목표 추적은 `현재 태스크 수 × CPU / 60`으로 원하는 수를 계산한다. 2개에서 평균 90~100%면 3.0~3.3 → 4개까지 늘어난다.
   - 늘림은 1분 지표 3개 연속 60% 초과(부하 시작 후 약 3~4분), 줄임은 15개 연속 54% 미만(부하 종료 후 약 15~20분)이다. 5분으로는 새 태스크가 부하를 나누기 전에 끝나서 유지 구간을 10분으로 늘렸다.
3. 부하 종료 후 태스크가 2개로 돌아올 때까지 기다린다.

다른 주소로 줄 때는 `-e BASE_URL=https://...`, 유지 시간은 `-e HOLD=15m`.

## 측정

| 항목 | 시작 | 끝 | 출처 |
|---|---|---|---|
| 스케일 아웃까지 시간 | 본 시험 시작(k6 시작 시각) | 원하는 태스크 수 변경, 새 타깃 healthy | `aws application-autoscaling describe-scaling-activities --service-namespace ecs --profile 3tier`, 타깃 그룹 |
| p95 | 구간별(아래) | | k6 `http_req_duration`(클라이언트), ALB `TargetResponseTime`(서버) |
| 스케일 인 | 부하 종료 | 원하는 태스크 수 2 | 위 명령 |
| 태스크당 처리량 | 보정에서 2개 평균 CPU 90% 근처 RPS ÷ 2 | | 보정 회차 |

### 구간별 p95 (스케일 아웃 전·후)

경계 시각은 `describe-scaling-activities`의 활동 시작 시각(원하는 수 변경)과 새 타깃이 healthy가 된 시각으로 잡는다. 경계가 둘이면 구간은 셋(늘어나기 전 / 새 태스크 기동 중 / 늘어난 뒤)이다.

- 클라이언트(k6): 원시 결과를 경계로 나눠 집계한다. 화면(목록·상세)별로도 나온다.

        node load/p95.mjs local/captures/E7/k6-main.csv <경계1 ISO 시각> <경계2 ISO 시각>

- 서버(ALB): 구간마다 한 번씩, 구간 길이를 `--period`로 주면 그 구간 전체의 p95 하나가 나온다. ALB 지표는 1분 단위라 시작·끝을 분 경계로 맞추고 `--period`는 60의 배수로 준다. `<ALB 차원>`은 대시보드 위젯의 LoadBalancer 값(`app/3tier-prod-alb/...`)이다.

        aws cloudwatch get-metric-statistics --profile 3tier --namespace AWS/ApplicationELB --metric-name TargetResponseTime --dimensions Name=LoadBalancer,Value=<ALB 차원> --start-time <구간 시작> --end-time <구간 끝> --period <구간 초> --extended-statistics p95

## 부하를 어디서 주나

로컬 PC(한국 가정망 → 서울 리전)에서 부하를 주도록 구성했다. 개인 프로젝트라 부하 발생용 인프라를 따로 두지 않았다.

- 클라이언트 p95(k6)에는 가정망 구간이 섞이므로 서버 처리 시간을 ALB `TargetResponseTime` p95로 따로 적었다. 두 값은 함께 비교하되 차이는 참고값으로만 본다. 두 백분위에 해당하는 요청이 서로 다를 수 있어서, 차이가 곧 망 구간 지연의 p95는 아니다.
- 부하 발생기가 병목이면 결과가 무효다. 시험 중 PC CPU를 함께 보고 80%를 넘은 회차는 버리기로 했다([k6 문서: 대규모 테스트 실행](https://grafana.com/docs/k6/latest/testing-guides/running-large-tests/)).
- 실무라면 대상과 같은 리전의 EC2에서 돌리거나 k6 Cloud(Grafana Cloud k6)로 여러 지역에서 준다. 망 구간이 빠지고 같은 조건으로 반복하기 쉽다.
