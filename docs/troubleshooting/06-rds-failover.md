# RDS Multi-AZ 장애 조치

RDS를 잠시 Multi-AZ로 켜고 강제 장애 조치(`reboot --force-failover`)를 일으켜, DB가 대기 인스턴스로 넘어가는 시간과 그동안 사용자가 받은 응답을 쟀다(#82). 평소에는 비용 때문에 Single-AZ로 둔다(DEC-7). 이 실험은 그 결정으로 감수한 위험이 Multi-AZ였다면 어느 정도로 줄어드는지 숫자로 남기려는 것이다.

| 항목 | 값 |
|---|---|
| 날짜 | 2026-11-05 11:01~11:18 KST |
| 환경 | prod (태스크 2개, AZ마다 1개), RDS db.t4g.micro gp3 20 GB, PostgreSQL |
| 조건 | 요청은 probe만. `/posts`(DB 왕복)와 `/actuator/health/liveness`(DB 없음)를 약 1초 간격, 요청당 최대 5초 |
| Single-AZ → Multi-AZ 변환 | **7분 45초** (11:01:34 → 11:09:19, RDS 이벤트). 그동안 서비스 영향 없음 |
| 장애 조치 (RDS 이벤트) | **43.3초** (시작 11:13:06.2 → 완료 11:13:49.4) |
| 사용자 영향 시간 (`/posts`) | **약 44초** (마지막 정상 요청 11:13:04 → 첫 정상 요청 11:13:49). 그 사이 요청 7건이 5초 안에 응답을 못 받음 |
| 장애 조치 완료 → 앱 회복 | **1초 미만** (완료 이벤트 11:13:49.4, 같은 초에 보낸 `/posts`가 0.12초에 200) |
| 5xx | **0건** (ALB Target·ELB 5xx 모두 0). 요청이 오류가 아니라 응답 없이 기다렸다 |
| liveness | 실험 내내 200, 태스크 교체 0건 |

## 재현 방법

1. Multi-AZ 켜기. 코드는 바꾸지 않고 로컬 apply에서 변수만 준다. plan은 `1 to add, 1 to change, 1 to destroy`(RDS `multi_az` false → true, 태스크 정의 새 리비전 1개)였다. RDS 모듈은 `apply_immediately = true`라 바로 변환이 시작된다.

        cd terraform/main
        terraform apply -var multi_az=true

2. probe 시작. 1초 간격으로 `/posts`와 `/actuator/health/liveness`의 상태 코드·응답 시간을 CSV로 남긴다.
3. 강제 장애 조치.

        aws rds reboot-db-instance --db-instance-identifier db-3tier-prod --force-failover

4. RDS 이벤트로 시작·완료 시각을 본다.

        aws rds describe-events --source-type db-instance --source-identifier db-3tier-prod --duration 30

5. 원복. 다음 CI apply(변수 기본값 false) 또는 세션 끝 destroy로 Single-AZ로 돌아간다. 측정 중에는 main에 인프라 변경을 머지하지 않는다(CI apply가 Single-AZ로 되돌린다).

## 증상

타임라인(KST):

| 시각 | 일 | 출처 |
|---|---|---|
| 11:01:34.5 | Multi-AZ 변환 시작 | RDS 이벤트 |
| 11:09:19.2 | 변환 완료. 주 DB 2c, 대기 DB 2a | RDS 이벤트, `describe-db-instances` |
| 11:13:04 | 마지막 정상 `/posts` (0.08초) | probe CSV |
| 11:13:05 | `/posts` 첫 실패(5초 안에 응답 없음). liveness는 200 | probe CSV |
| 11:13:06.2 | Multi-AZ instance failover started | RDS 이벤트 |
| 11:13:23.0 | DB instance restarted | RDS 이벤트 |
| 11:13:42 | 마지막 실패 요청(7번째) | probe CSV |
| 11:13:49.4 | Multi-AZ instance failover completed | RDS 이벤트 |
| 11:13:49 | `/posts` 200 (0.12초), 이후 정상 | probe CSV |

- 실패한 요청은 모두 상태 코드 없이 5초에서 끊겼다(probe의 `--max-time 5`). 앱은 DB 연결을 기다리며 요청을 붙잡고 있었고 오류를 돌려주지 않았다.
- ALB 지표: 11:13 분에 Target 2xx가 31건으로 앞뒤 분(86~88건)보다 줄었고, 5xx는 0건이었다. probe가 먼저 끊은 요청은 ALB에서 5xx가 아니라 클라이언트 종료로 남아 응답 시간 지표에도 잡히지 않는다.
- 장애 조치 뒤 DB 주소는 10.0.20.9(2a DB 서브넷 10.0.20.0/24)를 가리켰다. 그런데 `describe-db-instances`는 몇 분 뒤에도 주 DB를 2c로 보여 줬다. 어느 AZ가 주 DB인지는 API 속성보다 엔드포인트가 가리키는 IP로 확인하는 편이 확실했다.

## 해석

- **장애 조치 시간과 사용자 영향 시간이 거의 같았다(43초와 44초).** 앱이 끊긴 연결을 버리고 새 주 DB로 다시 붙는 데 추가 시간이 거의 들지 않았다. 엔드포인트 DNS가 바뀐 직후 HikariCP가 새 연결을 만들었다.
- **오류 대신 대기였다.** #43(DB 네트워크 차단 10분)에서는 약 30초 뒤 500(HikariCP connectionTimeout 30초)이 났다. 이번에는 장애 구간이 30초를 넘었지만 5xx가 0건이었다. 다만 probe가 5초에서 끊었기 때문에, 30초 넘게 기다린 사용자가 결국 200을 받았는지 500을 받았는지는 이 측정으로 알 수 없다.
- **5xx 비율 알람은 이런 장애를 못 잡는다.** 오류 응답이 없어서다. 응답 시간(p95)이나 요청 수 급감, RDS 이벤트 구독이 이 유형을 잡는 신호다.

## Single-AZ와 비교

| 상황 | Single-AZ(평소) | Multi-AZ(이번 실험) |
|---|---|---|
| DB 인스턴스 재시작·장애 | 재시작이 끝날 때까지 중단 | 약 44초 대기 뒤 회복 |
| DB가 있는 AZ 전체 장애 | AZ가 회복되거나 스냅샷에서 다른 AZ로 복원할 때까지 중단(수십 분 이상) | 같은 방식으로 다른 AZ로 넘어감 |
| 시간당 비용(db.t4g.micro + gp3 20 GB) | 0.03 USD | 약 0.06 USD |

세션만 띄우는 지금 운영에서는 Single-AZ를 유지한다(DEC-7). 24시간 운영으로 바뀌면 시간당 0.03 USD로 DB 중단을 약 44초로 줄일 수 있다는 것이 이 실험의 결론이다.

## 근거

- probe CSV: `local/captures/E8/probe-82.csv` (277줄, 실패 7줄)
- RDS 이벤트: `describe-events` 출력(위 타임라인)
- ALB 지표: `AWS/ApplicationELB` `HTTPCode_Target_5XX_Count`·`HTTPCode_ELB_5XX_Count`·`HTTPCode_Target_2XX_Count`, 11:11~11:17 1분 단위
