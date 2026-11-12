# 중앙 로그

앱 로그를 한곳에 모아 장애 원인을 로그만으로 찾을 수 있는지 확인했고, ELK, Loki, CloudWatch Logs를 비교했다.

## 1. 구성

```
앱 컨테이너(stdout, ECS JSON) ─ awsfirelens ─▶ Fluent Bit 사이드카(같은 태스크)
   ─ 피어링(운영 앱 SG → 관제 ELK SG :9200) ─▶ Elasticsearch app-board-YYYY.MM.DD
   ─▶ Kibana (SSM 포트 포워딩으로만 접속)
```

- 앱은 Spring Boot 구조화 로그로 Elastic Common Schema JSON을 낸다. 로그 한 줄이 문서 하나다. `log.level`, `message`, `error.*`, `url.path`, `http.response.status_code` 같은 필드와 FireLens가 붙인 태스크와 인스턴스 정보가 들어간다.
- 요청마다 ALB가 붙이는 `X-Amzn-Trace-Id`를 `http.request.id`로 남긴다. 같은 값으로 ALB 접근 로그와도 이을 수 있다.
- Fluent Bit 계정은 이 인덱스에 쓰기만 할 수 있다. Kibana는 SSM 포트 포워딩으로만 연다.
- 앱 로그는 CloudWatch Logs로 보내지 않는다. 라우터 자신의 로그만 간다. `enable_logging=false`로 띄우면 앱 로그가 CloudWatch Logs로 간다.
- Elasticsearch 서버의 사설 IP는 서브넷의 10번 주소로 고정했다. FireLens가 보내는 주소가 이 IP인데, 서비스는 태스크 정의 변경을 무시하게 해 뒀다. 서버가 바뀌어도 주소가 같아야 했다.

## 2. 로그로 원인 찾기

DB 서브넷을 FIS로 10분 막는 실험을 중앙 로그를 붙인 뒤 다시 하고, 원인을 Kibana에서만 찾아봤다(2026-11-05). 실험 조건과 사용자 영향, 시각은 [DB 연결 차단](troubleshooting/03-db-connection-failure.md)에 있다.

찾아간 순서는 이랬다. Kibana에서 `http.response.status_code:500`으로 첫 실패 요청을 찾았다. 그 요청의 `http.request.id`로 거르자 같은 요청 안에서 Hikari가 "연결이 닫혔다"고 남긴 WARN이 나왔다. `message:"Connection is not available"`(194건)과 `log.level:ERROR`로 DB 연결 풀이 바닥난 걸 확인했다. 문제가 DB로 가는 연결 경로에 있다는 결론까지 로그만으로 갔다.

처음 실험할 때는 로그가 CloudWatch Logs 평문이었다. 실패 줄을 문자열로 찾고 요청 기록과 RDS 지표로 앞뒤를 맞춰야 했다. 이번에는 필드 검색과 요청 ID로 "어떤 요청이 왜 실패했나"를 한 번에 이었다.

원인 줄은 알림보다 몇 분이나 먼저 로그에 남아 있었다. 이 차이를 줄이려고 Grafana에 앱 5xx 비율 규칙을 넣었다([관측과 알림](monitoring.md)).

## 3. 로그 스택 비교와 판단

이번 실험 약 20분(정상 구간과 10분 장애) 동안의 로그 양은 이랬다.

| 항목 | 값 |
|---|---|
| 문서 수 | 20,827 |
| 문서당 원본 크기 | 약 1 KB |
| Elasticsearch 저장 크기 | 4.95 MB (원본의 약 1/4) |
| 메모리 | Elasticsearch 1.53 GB, Kibana 1.06 GB (4 GiB 중) |

장애 중이라 평소보다 많다. 이 비율이 하루 내내 이어지면 원본은 하루 약 1.5 GB다. 그 양을 기준으로 서울 요금표로 계산했다.

| 월 비용 | CloudWatch Logs | ELK (이번 구성) | Loki (추정) |
|---|---|---|---|
| 하루 1.5 GB, 24시간 가동 | 약 35.6 USD | 약 33.1 USD | 약 15.5 USD |
| 세션만 가동 (월 80시간) | 쓴 만큼 (세션당 몇 센트) | 약 3.6 USD | 약 1.7 USD |

| 기준 | CloudWatch Logs | ELK | Loki |
|---|---|---|---|
| 검색 | Logs Insights, 스캔한 양만큼 과금 | 필드와 전문 색인, 집계가 강함 | 레이블로 좁힌 뒤 본문 검색 |
| 지표와 같은 화면 | CloudWatch 대시보드 | Kibana (지표는 Grafana에 따로) | Grafana에 같이 |
| 운영 부담 | 없음 | 힙, 디스크, 인덱스 수명, 버전 관리 | ELK보다 적음 |

- 이 프로젝트 규모에서는 CloudWatch Logs가 비용과 운영 모두 나았다. 하루 1.5 GB쯤에서 ELK와 비용이 비슷해지는데 평소 트래픽은 그보다 훨씬 적다. 그래도 ELK를 고른 건 필드 검색과 요청 ID 추적을 직접 해 보려는 목적이었고, 2절에서 그 효과를 확인했다.
- 규모가 커지면 수집 요금 때문에 직접 설치가 유리해진다. 지표가 이미 Grafana에 있다면 메모리와 저장 비용, 화면 통합 면에서 Loki가 ELK보다 맞다. 전문 검색과 복잡한 집계가 중요하면 ELK나 관리형 OpenSearch다.
- Loki는 설치해서 재지 않았다. 표의 Loki 값은 요금표로 계산한 추정이다.

## 4. 한계와 개선 방향

겪은 문제와 한계:
- 로그 경로가 하나뿐이었다. FireLens가 보낼 때의 출발지 Security Group을 잘못 지정해 로그가 10분 동안 사라졌다. CloudWatch Logs로 같이 보내지 않아서 되살릴 수 없었다. FireLens 사이드카는 앱 태스크의 네트워크 인터페이스로 나가서 호스트에서 도는 데몬과 출발지가 다르다는 걸 이때 알았다.
- Elasticsearch 동적 매핑은 날짜별 인덱스의 첫 문서가 정한다. 그날 첫 줄이 JSON이 아닌 JVM 경고였더니 `log` 필드가 텍스트로 굳어 그날 JSON 로그가 전부 거부됐다. 인덱스 템플릿으로 `log`를 객체로 고정하고, JSON이 아닌 줄은 수집 파이프라인에서 `message`로 옮기게 했다. 로컬 Elasticsearch에서 같은 순서로 재현해 확인했다.

개선 방향:
- 로그를 CloudWatch Logs와 Elasticsearch 두 곳으로 보내면 한쪽 경로가 막혀도 남는다. Fluent Bit은 한 입력을 여러 출력으로 보낼 수 있다([Fluent Bit 라우팅](https://docs.fluentbit.io/manual/data-pipeline/router)).
- Fluent Bit 버퍼를 파일 시스템에 두면 출력이 막혔을 때 메모리 버퍼보다 덜 잃는다. 다만 저장 한도를 넘으면 오래된 데이터부터 버린다([Fluent Bit 버퍼링](https://docs.fluentbit.io/manual/administration/buffering-and-storage)).
- 날짜별 인덱스에 ILM 정책을 붙이면 보존 기간이 지난 인덱스를 자동으로 지운다. 지금은 관제 VPC를 세션마다 지워서 필요 없었지만 계속 운영하면 있어야 한다([Elasticsearch ILM](https://www.elastic.co/docs/manage-data/lifecycle/index-lifecycle-management)).
