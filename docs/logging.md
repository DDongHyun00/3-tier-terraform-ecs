# 중앙 로그: 장애 추적 시나리오와 ELK·Loki·CloudWatch Logs 비교 (E12 #100)

E12에서 앱 로그를 ECS JSON(#99)으로 내고 FireLens(#98)로 관제 VPC의 Elasticsearch·Kibana(#97)에 모았다. 이 문서는 ① 실제 장애 1건을 로그만으로 추적한 기록과 ② 세 로그 스택의 비교를 남긴다. 측정값의 원본은 Notion 실측 기록 DB다.

## 1. 구성

```
앱 컨테이너(stdout, ECS JSON) ─ awsfirelens ─▶ Fluent Bit 사이드카(같은 태스크)
   ─ 피어링(운영 앱 SG → 관제 ELK SG :9200, 계정 fluentbit) ─▶ Elasticsearch app-board-YYYY.MM.DD
   ─▶ Kibana(데이터 뷰 app-board-*, SSM 포트 포워딩으로만 접속)
```

- 문서 하나 = 로그 한 줄. 앱 필드(`@timestamp`, `log.level`, `log.logger`, `message`, `error.*`, `http.request.id`, `http.request.method`, `http.response.status_code`, `url.path`, `event.duration_ms`)와 FireLens가 붙인 ECS 메타데이터(`ecs_cluster`, `ecs_task_arn`, `ecs_task_definition`, `ec2_instance_id`)가 들어간다.
- `http.request.id`는 ALB가 붙이는 `X-Amzn-Trace-Id`다. ALB 접근 로그와도 같은 값으로 이을 수 있다.
- 인덱스 템플릿 `app-board`가 `log`를 객체로 고정하고, 기본 수집 파이프라인 `app-board-normalize`가 JSON이 아닌 줄(JVM 경고 등)의 문자열 `log`를 `message`(이미 있으면 `log_raw`)로 옮긴다(#144). 이 처리 전에는 날짜별 인덱스의 첫 문서가 평문이면 `log`가 text로 굳어 그날 JSON 로그가 모두 `document_parsing_exception`으로 거부됐다(11/05 운영에서 발생, 로컬 ES 9.5.5에서 같은 순서로 재현).
- ELK 서버 사설 IP는 서브넷의 10번 호스트로 고정했다. FireLens 출력 주소가 이 IP이고, 서비스는 태스크 정의 변경을 무시하므로 서버가 교체돼도 주소가 같아야 한다.

## 2. 장애 추적: DB 연결 차단 (2026-11-05)

E08 #43과 같은 FIS 실험(DB 서브넷 네트워크 ACL 차단 10분)을 다시 돌리고, Kibana(Elasticsearch 질의)로 원인을 찾았다. 조건은 ECS on EC2 태스크 2개, probe 1초 간격(`/posts`, `/actuator/health`, `/actuator/health/liveness`).

| 시각 (UTC) | 사건 | 차단 시작부터 |
|---|---|---|
| 16:28:44.0 | FIS 차단 시작 | 0 |
| 16:28:54.7 | WARN `HikariPool-1 - Failed to validate connection ... (This connection has been closed.)`, 요청 ID `Root=1-6aeb5d3c-…` | **10.7초** |
| 16:29:14.7 | `GET /posts 500 30020ms`, **같은 요청 ID** | 30.7초 |
| 16:29:30.0 | ERROR `CannotCreateTransactionException: Could not open JPA EntityManager for transaction`(스케줄 작업) | 46초 |
| 16:34:42.6 | CloudWatch `alb-5xx-rate` ALARM(비상 알람) | 5분 58.6초 |
| 16:38:43.5 | 사용자 쪽 첫 정상 응답(이전 요청이 대기 끝에 200) | 9분 59.5초 |
| 16:38:45.7 | FIS 차단 종료 | |

- 사용자 영향: `/posts` 500·`/actuator/health` 503 각 566건, liveness 실패 0(태스크 교체 없음, E08과 같은 설계 의도).
- **추적 과정**: Kibana에서 `http.response.status_code:500`으로 첫 실패 요청을 찾고, 그 `http.request.id`로 필터하면 같은 요청 안에서 Hikari가 "연결이 닫혔다"고 남긴 WARN이 나온다. 이어서 `message:"Connection is not available"`(194건)과 `log.level:ERROR`가 DB 연결 풀 고갈을 확인해 준다. 앱 코드가 아니라 DB 연결 경로 문제라는 결론까지 로그만으로 갈 수 있었다.
- **탐지**: 로그에는 10.7초 만에 원인 줄이 있었지만 알림은 CloudWatch 비상 알람(5분 58.6초)뿐이었다. Grafana 규칙(CPU·타깃 0개·RDS)은 이 장애를 보지 않는다. 앱 5xx 비율 규칙(`http_server_requests_seconds_count{status=~"5.."}`)을 Grafana에 더하는 것이 다음 후보다.
- E08(Fargate, CloudWatch Logs 평문) 때는 실패 줄(`Connection is not available, request timed out after 30000ms`)을 문자열로 찾고 probe·RDS 지표로 앞뒤를 맞췄다. 이번에는 필드 검색과 요청 ID로 "어떤 요청이 왜 실패했는지"를 한 번에 이었다.

## 3. 비교: ELK vs Loki vs CloudWatch Logs

### 3.1 이번 세션의 로그 양 (실측)

| 항목 | 값 |
|---|---|
| 약 20분(정상 + 10분 장애)의 문서 수 | 20,827 |
| 문서당 원본 크기(평균) | 약 1 KB(995 B) |
| Elasticsearch 저장 크기 | 4.95 MB(원본 약 20.7 MB의 약 1/4) |
| 메모리 | Elasticsearch 1.53 GB, Kibana 1.06 GB(t4g.medium 4 GiB 중) |

장애 중에는 요청마다 WARN이 여러 줄 남아 평소보다 양이 많다. 이 비율이 하루 내내 이어지면 원본 약 1.5 GB/일이다.

### 3.2 비용 (서울 요금표, 2026-11-05 Price List API)

| 항목 | CloudWatch Logs | ELK(직접 설치, 이번 구성) | Loki(직접 설치, 추정) |
|---|---|---|---|
| 수집 | Standard GB당 0.76 USD(Infrequent Access 0.38) | 0 | 0 |
| 저장 | GB-월 0.0314 USD | 서버 디스크(gp3 30 GB, 월 2.74 USD) | 객체 저장소(S3 Standard 서울 GB-월 약 0.025 USD) |
| 검색 | Logs Insights 스캔 GB당 0.0076 USD | 0 | 0 |
| 서버 | 없음 | t4g.medium 0.0416 USD/시간(월 30.37 USD) | 작은 인스턴스로 가능(예: t4g.small 0.0208 USD/시간) |
| **원본 1.5 GB/일, 24시간 가동, 월** | 수집 34.2 + 저장 약 1.4 = **약 35.6 USD** | **약 33.1 USD**(고정) | 서버 15.2 + S3 약 0.3 = **약 15.5 USD** |
| 세션만 가동(월 80시간) | 쓴 양만큼(세션당 몇 센트) | 약 3.6 USD | 약 1.7 USD |

- 하루 원본 약 1.5 GB부터 24시간 가동 기준으로 ELK와 CloudWatch Logs의 비용이 비슷해진다. 이보다 적으면 CloudWatch Logs가 싸고, 많으면 직접 설치가 싸다. 이 프로젝트의 평소 트래픽(장애 없음)은 이보다 훨씬 적어서 **비용만 보면 CloudWatch Logs가 맞다**.
- Loki는 전문(full-text) 색인 없이 레이블만 색인하고 본문은 압축 덩어리로 객체 저장소에 둔다. 그래서 메모리·저장 비용이 ELK보다 작다. 위 Loki 열은 요금표로 계산한 추정이고 이번에 설치·측정하지는 않았다.

### 3.3 기능·운영

| 기준 | CloudWatch Logs | ELK | Loki |
|---|---|---|---|
| 검색 | Logs Insights 질의(JSON 필드 자동 인식), 스캔한 양만큼 과금 | 필드·전문 색인. 집계·대시보드(Kibana)가 강함 | 레이블로 좁힌 뒤 본문 grep(LogQL). 필드 집계는 질의 때 파싱 |
| 지표와 같은 화면 | CloudWatch 대시보드 | Kibana(지표는 Grafana와 따로) | **Grafana에 같이**(이미 E11 Grafana가 있다) |
| 메모리 | 없음 | 큼(이번 2.6 GB) | 작음(레이블 색인만) |
| 운영 부담 | 없음(관리형), 보존 기간만 정함 | 힙·디스크 워터마크·인덱스 수명주기·보안 설정·버전 업그레이드 | ELK보다 적음. 레이블 설계를 잘못하면 성능 문제(카디널리티) |
| 수집 경로 | awslogs 드라이버(설정 없음) | FireLens 사이드카 + SG·피어링·계정 | FireLens 또는 Promtail·Alloy |
| 이번에 겪은 문제 | 없음 | 출발지 SG 실수로 로그 10분 유실, 앱 로그를 CloudWatch와 병행하지 않아 복구 불가. 동적 매핑 충돌로 하루치 JSON 로그 거부(#144) | (미설치) |

### 3.4 판단

- **이 프로젝트 규모**: 로그 양이 적고 1인 운영이라 CloudWatch Logs(관리형)가 비용·운영 모두 유리하다. ELK를 고른 결정(E12 설계 "중앙 로그는 ELK, Loki는 비교군")은 비용이 아니라 **필드 검색·요청 ID 추적 경험**과 직접 운영 경험을 얻기 위해서였고, 위 시나리오에서 그 효과를 확인했다.
- **규모가 커지면**: 하루 원본이 GB 단위를 넘으면 수집 요금 때문에 직접 설치가 유리해진다. 그때 지표가 이미 Grafana에 있다면 Loki가 메모리·저장 비용과 화면 통합에서 ELK보다 맞다. 전문 검색·복잡한 집계가 핵심이면 ELK(또는 관리형 OpenSearch)다.
- **이번 구성의 약점**: 로그 경로가 하나뿐이라 Elasticsearch나 경로가 막히면 로그가 사라진다(실제로 10분 유실). 운영이라면 CloudWatch Logs나 S3로의 보조 출력을 두거나, Fluent Bit 파일 버퍼를 켠다.
