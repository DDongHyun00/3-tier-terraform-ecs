# DB 연결 실패

앱 태스크와 RDS 사이 네트워크를 10분 동안 끊고, liveness·health·알람이 설계대로 동작하는지 확인했다. DB가 끊겨도 태스크가 교체되지 않아야 하고, 장애는 알람으로 잡혀야 한다.

| 항목 | 값 |
|---|---|
| 날짜 | 2026-11-02 01:03~01:13 KST |
| 환경 | prod (당시는 스테이징 구축 전이라 환경이 운영 하나뿐이고 실사용자가 없는 데모여서 운영에서 의도적으로 실험. 실무라면 스테이징) |
| 조건 | 태스크 2개(AZ마다 1개), RDS Single-AZ, 요청은 probe 1초 간격(3개 URL)만 |
| 사용자 영향 시간 | **약 10분 0초** (게시판·health 첫 실패 01:03:38.1 ~ 마지막 실패 응답 01:13:37.9) |
| 복구 시간 (차단 해제 → 첫 정상 응답) | **1초 미만** (차단 종료 01:13:39.3, 대기 중이던 `/posts`가 01:13:38.7에 200) |
| 태스크 교체 | **0건** (실험 내내 running 2/2, 타깃 2개 healthy) |
| 울린 알람 | 5xx 비율만, **차단 시작 6분 11초 뒤** (01:09:49.7 ALARM). 목표 "탐지 5분 이내" 미달 |

## 재현 방법

차단은 AWS FIS 실험 템플릿 `3tier-db-disrupt`(`terraform/bootstrap/fis.tf`)로 했다. 액션 `aws:network:disrupt-connectivity`가 DB 서브넷 2개(태그 `Project`·`Tier=db`)의 NACL을 복제해 deny 규칙을 넣고 서브넷에 붙인다. `duration PT10M`이 지나면 FIS가 복제 NACL을 지우고 원래 NACL로 되돌린다.

1. 사전 조건: bootstrap apply로 실험 역할 `3tier-fis`와 템플릿이 있고, main이 apply 상태(서비스 안정, 알람 5개 OK).
2. probe 시작(계속 켜 둔다). 1초 간격으로 `/posts`, `/actuator/health`, `/actuator/health/liveness`를 호출해 시각·상태 코드·응답 시간을 CSV로 남긴다. 평시 5분을 먼저 잰다.
3. 실험 시작. 템플릿 ID는 bootstrap 출력 `fis_db_disrupt_template_id`.

        aws fis start-experiment --experiment-template-id <ID> --profile 3tier

4. 10분 동안 probe, ECS 서비스 이벤트, 알람 상태를 본다.
5. 자동 원복. 실험 상태가 `completed`가 되면 원래 NACL로 돌아온 것이다.

        aws fis get-experiment --id <실험 ID> --profile 3tier

6. 중간에 멈춰야 하면 수동 중지. 중지해도 FIS가 원복한다.

        aws fis stop-experiment --id <실험 ID> --profile 3tier

7. 원복 뒤 5분 더 probe를 돌려 회복을 잰다. 실험이 끝나기 전에는 main을 destroy하지 않는다(복제 NACL이 남아 VPC 삭제가 실패한다).

## 예상 동작

앱 설정 기준: HikariCP 기본값(풀 10, connectionTimeout 30초, validationTimeout 5초, maxLifetime 30분), PostgreSQL JDBC 기본값(connectTimeout 10초, socketTimeout 0 = 무제한).

| 대상 | 예상 | 이유 |
|---|---|---|
| `/actuator/health/liveness` | 200 유지, 태스크 교체 없음 | DB를 보지 않는다. ALB 헬스체크는 쿠키가 없어 세션(JDBC) 조회도 하지 않는다 |
| `/actuator/health` | 약 30초 걸려 503 | DB 지표가 풀에서 연결을 얻으려다 connectionTimeout 30초 |
| `/posts` (게시판) | 약 30초 걸려 500, 또는 60초 넘게 매달려 ALB 504 | 놀던 연결은 검증 5초 실패 → 새 연결이 막혀 30초 후 예외. 쿼리 도중이던 연결은 socketTimeout이 없어 TCP 재전송이 끝날 때까지 매달리고, ALB 유휴 시간 60초에 504 |
| 5xx 비율 알람 (`3tier-prod-alb-5xx-rate`) | 울림 | 5% 초과가 5분 중 3분. probe가 1초 간격(URL 3개)이라 분당 최소 요청 수 10건을 넘는다 |
| RDS 연결 수 알람 (`3tier-prod-rds-connections-high`) | 안 울림 | 임계는 60 초과뿐이다. 연결 수는 그대로거나 줄어든다 |
| 비정상 타깃 알람 (`3tier-prod-alb-unhealthy-targets`) | 안 울림 | liveness가 200이다. 울리면 그 자체가 발견이다 |

## 증상

타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 01:03:13.3 | `fis start-experiment` 요청, 실험 EXPzjjz7Ezqw8ijXfp | CLI 출력 |
| 01:03:38.1 | 차단 action 시작(요청 후 약 25초) | `fis get-experiment` |
| 01:03:38.1 | probe 첫 실패(`/posts` 500, `/actuator/health` 503, 각각 약 30초 대기 뒤) | probe CSV |
| 01:04~01:12 | ALB Target 5xx 분당 104~120건 | CloudWatch |
| 01:07~01:09 | RDS `DatabaseConnections` 20 → 19 → 9 → 0 | CloudWatch |
| 01:09:49.7 | `3tier-prod-alb-5xx-rate` OK → ALARM | 알람 이력 |
| 01:13:08.9 | 이때 시작한 `/posts`가 29.8초 대기 뒤 01:13:38.7에 200 | probe CSV |
| 01:13:39.3 | 차단 action 종료, 실험 completed(01:13:39.6) | `fis get-experiment` |
| 01:13~ | RDS `DatabaseConnections` 20으로 회복 | CloudWatch |

probe(01:03~01:14): liveness 666회 실패 0, `/actuator/health` 666회 중 565회 503, `/posts` 666회 중 565회 500. 실패는 모두 약 30초 대기 뒤였고 ALB 504는 없었다.

ECS 서비스 이벤트: 실험 동안 태스크 시작·중지·등록 해제 이벤트 없음. 비정상 타깃 알람, RDS 연결 수 알람 상태 변화 없음.

캡처: 콘솔 캡처 대신 위 CLI 결과와 5초 간격 상태 기록(CSV)으로 남겼다.

## 원인

- **SG가 아니라 NACL로 끊은 이유**: sg-db의 인바운드 규칙은 SG 참조라 연결 추적 대상이다. 규칙을 지워도 이미 맺은 연결은 끊기지 않는다(AWS 문서: 즉시 차단하려면 NACL을 쓴다, https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-connection-tracking.html). Hikari 풀은 연결을 최대 30분(maxLifetime) 재사용하므로 SG만 지우면 장애가 최대 30분에 걸쳐 조금씩 나타난다. NACL은 상태가 없어 패킷 단위로 바로 막힌다.
- **liveness가 DB를 보지 않는 이유**: DB 장애 때 ALB 헬스체크가 실패하면 ECS가 정상 태스크를 계속 교체한다. 교체해도 DB는 돌아오지 않으므로 교체 루프만 생긴다(E01 헬스체크 결정).
- **응답이 30초 넘게 걸리는 이유**: Hikari connectionTimeout 30초 동안 연결을 기다린다. 이미 쿼리를 보낸 연결은 socketTimeout이 없어 OS의 TCP 재전송 한도까지 기다린다.

## 해결

- 차단 해제는 FIS가 자동으로 했다(복제 NACL 삭제, 원래 NACL 재연결).
- Hikari 재연결 확인: 해제 시각 → probe의 첫 `/posts` 200, 첫 `/actuator/health` 200까지 시간을 잰다. 로그는 INFO라 실패 줄(`Connection is not available, request timed out after 30000ms`)은 남고 재연결 성공 줄은 안 남을 수 있어서, probe 결과와 RDS `DatabaseConnections` 회복(태스크 2개 × 풀 10 = 약 20)으로 확인한다.
- 측정: 차단 종료(01:13:39.3) 직전부터 대기하던 요청이 성공해 재연결 지연은 1초 미만이었다. RDS 연결 수는 01:13분에 20(태스크 2개 × 풀 10)으로 돌아왔다.

## 재발 방지

- 지금 설정이 막는 것: DB 장애가 태스크 교체 루프로 번지지 않는다(liveness 분리). 장애는 5xx 비율 알람이 Slack으로 알린다.
- 남은 위험: 매달린 요청이 Tomcat 스레드(기본 200)를 다 쓰면 liveness도 응답하지 못해 태스크가 교체된다. 이번 실험은 probe 1초 간격이라 동시 요청이 약 60건(30초 대기 × DB를 쓰는 URL 2개의 초당 2건)이어서 여유가 컸다. 실제 트래픽에서는 일어날 수 있다.
- 제안(구현 안 함): JDBC `socketTimeout`과 쿼리 타임아웃을 두어 매달린 요청을 수 초 안에 실패시킨다. 앱 설정 변경이라 이 이슈 범위 밖이다.
- 제안(구현 안 함): FIS 템플릿 중지 조건에 비정상 타깃 알람을 걸어, 태스크 교체가 시작되면 실험을 자동으로 멈춘다.

## 예상과 달랐던 것

- ALB 504는 한 건도 없었다. 쿼리 도중 매달린 연결 대신, 놀던 연결의 검증 실패 → 새 연결 대기 30초 경로만 나타났다. 요청이 1초 간격으로 짧게 끝나 쿼리 도중인 연결이 거의 없었기 때문으로 본다.
- RDS 쪽 연결 수는 차단 직후가 아니라 3~5분 뒤(01:07~01:09)에 0이 됐다. 패킷이 막혀 RDS가 연결 종료를 늦게 알아차렸기 때문이다.
- 5xx 비율 알람은 Target 5xx가 01:04분부터 분당 100건을 넘었는데도 01:09:49에 울렸다. 5분 중 3분 조건(최소 약 3분)에 ALB 지표 반영 지연이 더해져 차단 시작 후 6분 11초가 걸렸다. 목표 "장애 탐지 5분 이내"는 미달이다. E12에서 같은 시나리오를 다시 잰 결과는 [logging.md](../logging.md) 2절에 있다. 그때도 Grafana 규칙은 이 장애를 보지 못해 앱 5xx 비율 규칙 AppHttp5xxRate를 더했고(#131), 시험에서 500 발생 1분 27.7초 뒤 알림이 발송됐다.

