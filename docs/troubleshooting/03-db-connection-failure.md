# DB 연결 차단

앱 태스크와 RDS 사이 네트워크를 10분 동안 끊고, DB가 끊겨도 태스크가 교체되지 않는지와 장애가 알람으로 잡히는지 확인했다.

## 요약

2026-11-02 01:03~01:13 KST에 태스크 2개(가용 영역마다 1개), RDS Single-AZ로 쟀다. 요청은 1초 간격 probe(URL 3개)뿐이었다.

운영 DB를 직접 막은 실험이다. 스테이징이 생기기 전이었고 실사용자가 없어서 할 수 있었다.

| 항목 | 값 |
|---|---|
| 사용자 영향 | `/posts`와 health 약 10분 0초 실패, liveness는 실패 0 |
| 차단 해제부터 정상 응답까지 | 1초 미만 |
| 태스크 교체 | 0건 |
| 울린 알람 | 5xx 비율 알람 하나, 차단 시작 6분 11초 뒤 |

탐지는 목표 "5분 이내"에 미달했다.

## 재현

차단은 AWS FIS 실험 템플릿 `3tier-db-disrupt`(`terraform/bootstrap/fis.tf`)로 했다. `aws:network:disrupt-connectivity` 액션이 DB 서브넷 2개의 NACL을 복제해 모든 트래픽을 막는 규칙을 넣고 서브넷에 붙인다. 10분(`PT10M`)이 지나면 FIS가 복제 NACL을 지우고 원래 NACL로 되돌린다.

1. 1초 간격으로 `/posts`, `/actuator/health`, `/actuator/health/liveness`를 요청해 기록한다. 평시 5분을 먼저 잰다.
2. 실험을 시작한다. 템플릿 ID는 bootstrap 출력 `fis_db_disrupt_template_id`에 있다.

        aws fis start-experiment --experiment-template-id <ID> --profile 3tier

3. 실험 상태가 `completed`가 되면 원래 NACL로 돌아온 것이다. 중간에 멈춰도 FIS가 되돌린다.

        aws fis get-experiment --id <실험 ID> --profile 3tier
        aws fis stop-experiment --id <실험 ID> --profile 3tier

실험이 끝나기 전에 main을 destroy하면 안 된다. 복제 NACL이 남아 VPC 삭제가 실패한다.

### 예상

앱은 HikariCP 기본값(풀 10, 연결 대기 30초, 검증 5초)과 PostgreSQL JDBC 기본값(연결 10초, 소켓 타임아웃 없음)을 썼다.

| 대상 | 예상 | 이유 |
|---|---|---|
| liveness | 200 유지, 태스크 교체 없음 | DB를 보지 않는다 |
| `/actuator/health` | 약 30초 뒤 503 | 풀에서 연결을 30초 기다린다 |
| `/posts` | 약 30초 뒤 500, 또는 60초 넘게 매달려 ALB 504 | 쿼리 도중인 연결은 소켓 타임아웃이 없어 오래 매달린다 |
| 5xx 비율 알람 | 울림 | 5분 중 3분 동안 5%를 넘는다 |
| 비정상 타깃 알람 | 안 울림 | liveness가 200이다 |

## 무슨 일이 있었나

| 시각 (KST) | 일 |
|---|---|
| 01:03:13 | 실험 시작 요청 |
| 01:03:38 | 차단 시작, 첫 실패(`/posts` 500, health 503, 각각 약 30초 대기 뒤) |
| 01:07 ~ 01:09 | RDS 연결 수 20에서 0으로 감소 |
| 01:09:49 | 5xx 비율 알람 울림 |
| 01:13:38 | 대기 중이던 `/posts`가 200 |
| 01:13:39 | 차단 종료 |

probe 결과는 이렇다. liveness는 666회 중 실패 0이었다. `/actuator/health`는 666회 중 565회가 503, `/posts`는 666회 중 565회가 500이었다. 실패는 모두 약 30초를 기다린 뒤였다. 실험 동안 ECS 태스크는 시작, 중지, 등록 해제가 한 번도 없었다.

예상과 다른 점도 있었다. ALB 504는 한 건도 없었다. 요청이 1초 간격으로 짧게 끝나 쿼리 도중에 끊긴 연결이 거의 없었고, 쉬던 연결이 검증에 실패한 뒤 새 연결을 30초 기다리는 경로만 나타난 것으로 본다. RDS 쪽 연결 수는 차단하고 3~5분이 지나서야 0이 됐다. 패킷이 막혀서 RDS가 연결이 끊긴 걸 늦게 알아차렸다.

5xx 비율 알람은 01:04부터 분당 100건 넘게 5xx가 났는데도 01:09:49에야 울렸다. "5분 중 3분" 조건에 최소 3분이 걸리고, ALB 지표가 들어오는 지연이 더해져 6분 11초가 됐다.

## 원인

- 보안 그룹 대신 NACL로 끊었다. 보안 그룹 규칙은 연결을 추적하기 때문에 규칙을 지워도 이미 맺은 연결은 끊기지 않는다([보안 그룹 연결 추적](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-connection-tracking.html)). Hikari는 연결을 최대 30분 재사용하므로 보안 그룹만 바꾸면 장애가 30분에 걸쳐 조금씩 나타난다. NACL은 상태가 없어 패킷 단위로 바로 막힌다.
- liveness는 일부러 DB를 보지 않게 했다. DB 장애 때 ALB 헬스체크가 실패하면 ECS가 멀쩡한 태스크를 계속 교체한다. 교체해도 DB는 돌아오지 않으니 교체 루프만 생긴다.
- 응답이 30초 넘게 걸린 건 Hikari가 연결을 30초 기다리기 때문이다.

## 조치와 재발 방지

차단 해제는 FIS가 자동으로 했다. 해제 직전부터 기다리던 요청이 바로 성공해 재연결 지연은 1초 미만이었다. RDS 연결 수도 01:13에 20(태스크 2개 × 풀 10)으로 돌아왔다. 재연결 성공은 로그에 남지 않아서 probe와 RDS 연결 수로 확인했다.

지금 설정의 보호 장치:
- DB 장애가 태스크 교체 루프로 번지지 않는다.
- 장애는 5xx 비율 알람이 Slack으로 알린다.
## 다시 잰 결과 (중앙 로그 구축 뒤)

2026-11-05 01:28 KST에 ECS on EC2 태스크 2개로 같은 실험을 다시 했다. 이번에는 앱 로그가 Elasticsearch로 모이는 상태였다.

| 항목 | 2026-11-02 | 2026-11-05 |
|---|---|---|
| `/posts` 500, health 503 | 각 565건 | 각 566건 |
| liveness 실패 | 0 | 0 |
| 5xx 비율 알람 | 6분 11초 | 5분 58.6초 |
| 로그에 원인 줄이 남기까지 | 확인 안 함 | 10.7초 |

- 차단 10.7초 뒤 Hikari가 "연결이 닫혔다"는 경고를 남겼고, 같은 요청 ID로 30.7초에 500 응답이 이어졌다. 로그만으로 원인이 DB 연결 경로라는 걸 알 수 있었다([logging.md](../logging.md)).
- 첫 정상 응답은 차단 시작 9분 59.5초 뒤였다.
- Grafana 규칙(CPU, 앱 태스크 수, RDS)은 이 장애를 하나도 잡지 못했다. 그래서 앱 5xx 비율 규칙을 Grafana에 추가했고, 시험에서 500이 나고 1분 27.7초 뒤 알림이 나갔다.

## 배운 점과 개선 방향

배운 점:
- liveness를 DB와 떼어 둔 덕분에 DB 장애가 태스크 교체로 번지지 않았다. 대신 요청은 DB 연결을 30초 기다린 뒤에야 실패해서, 사용자는 오류를 받기까지 30초씩 기다렸다.
- 로그에는 원인이 10.7초 만에 남았는데 알람은 5분 58.6초 뒤에 울렸다. 앱 오류를 보는 Grafana 규칙이 없었다.

개선 방향:
- 연결 대기 시간(`connectionTimeout`, 기본 30초)을 줄이고 JDBC 소켓 타임아웃과 쿼리 타임아웃을 두면 된다. 매달린 요청이 몇 초 안에 실패해서 Tomcat 스레드(기본 200)가 바닥나지 않는다. 스레드가 바닥나면 liveness도 응답하지 못해 태스크가 교체된다. 이번에는 동시 요청이 약 60건이라 여유가 있었다([HikariCP](https://github.com/brettwooldridge/HikariCP)).
- liveness는 지금처럼 DB와 떼어 두는 게 맞다. Spring Boot 문서도 liveness가 외부 시스템에 의존하면 안 된다고 한다. readiness에 DB 점검을 넣을지는 DB 장애 때 트래픽을 어디로 보낼지에 따라 정하면 된다([Spring Boot health groups](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html)).
- FIS 실험의 중지 조건에 비정상 타깃 알람을 걸면 태스크 교체가 시작될 때 실험이 자동으로 멈춘다. Well-Architected도 이런 장애 주입 실험을 정기적으로 돌리라고 권한다([REL12-BP04](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_testing_resiliency_failure_injection_resiliency.html)).
