# DEC-32. ECS CPU·RDS 연결 알람은 결측을 missing으로 두고 5분 중 3분으로 평가한다

- 상태: 확정 · 날짜: 2026-10-30 · 검증: 실측 완료
- 관련 이슈: https://github.com/DDongHyun00/3-tier-terraform-ecs/issues/80

## 배경

10/29 부하 시험에서 ECS 서비스 CPU가 6분간 93~98%였는데 `3tier-prod-ecs-cpu-high`(80% 초과, 60초 × 5/5, notBreaching)가 울리지 않았다. 알람 이력으로 재보니 ECS 서비스 지표는 평가 시점보다 약 3분 50초 늦게 도착했고(네 번 모두 3분 36초~3분 56초), 그 빈 구간을 notBreaching이 정상으로 채워 "5개 전부 초과"가 성립할 수 없었다.

## 결정 요인

- [AWS 권장 알람 문서](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)의 ECS CPUUtilization 권장값은 Average, 80, 60초, 5/5이고 결측 처리는 기본값(missing)이다. 내 설정과 다른 건 결측 처리 하나였다.
- [CloudWatch 결측 처리 문서](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarms-and-missing-data.html)는 데이터가 늦거나 끊기는 지표에 M of N을 쓰라고 안내한다.
- 같은 지표를 보는 목표 추적 알람(AWS 생성, missing)은 정상으로 울렸다.

## 검토한 선택지

- A. 결측만 missing으로(5/5 유지): 표준 그대로. 10/29 부하 시험 기록에 대입하면 16:13에 울림. 한 분이라도 80 미만이면 연속이 끊긴다.
- B. A + 5분 중 3분(3 of 5): 표준에서 민감도만 조정. 10/29 부하 시험 기록에 대입하면 16:11에 울리고, 한두 분 빠지거나 출렁여도 울린다. 톱니 모양(95/70/95/70/95) 부하에도 울리는 쪽이 체감과 맞다고 봤다.
- C. 5분 평균 1회: 단순하지만 짧고 센 폭주에 둔하다.
- 세 개 모두 10/29 부하 시험 상황은 잡는다. 차이는 울리는 시각과 출렁임 내성이다.

## 결정

B. `3tier-prod-ecs-cpu-high`와 `3tier-prod-rds-connections-high` 두 개를 결측 missing(기본값) + 평가 5개 중 3개로 바꾼다. ALB 5xx 비율은 건수 기반이라 notBreaching을 유지하고(이미 3/5), 비정상 타깃(2/2)과 여유 스토리지(1회)는 그대로 둔다. 이슈 #38의 "CPU >80% 5분"은 "5분 중 3분"으로 읽는다.

## 결과

- 얻을 것: 지표가 4분 늦어도 과부하 시작 후 약 6분에 알람. 설정 처리가 "연속 지표는 missing, 건수 지표는 notBreaching"으로 정리된다.
- 감수한 것: 5분 중 3분만 80%를 넘으면 울리므로, 나머지 2분이 80% 아래로 내려가는 톱니 모양 부하에도 울린다. 오경보로 느껴지면 4/5로 올린다.
- 실측(2026-11-02, E08 세션): PR #81 머지 뒤 같은 k6 200 RPS 부하에서 ecs-cpu-high가 01:25:15.6 KST에 OK → ALARM이 됐고 SNS 액션도 성공했다(전달 1, 실패 0). E07에서는 6분간 93~98%였는데도 울리지 않았다.
- 과부하(1분 평균 99.5%)가 시작된 01:20부터 5분 15초, k6 시작부터 5분 58초. 품질 목표 "장애 탐지 5분 이내"에는 15초 못 미쳤다. 지표가 약 4분 늦게 들어오는 구조는 그대로라 알람 조정만으로는 5분 안쪽이 어렵다. E11에서 다시 쟀다: Grafana 4분 10초, CloudWatch 6분 26초([monitoring.md](../monitoring.md)).
- 부하가 끝난 뒤 01:31:15.6에 OK로 돌아왔다(전달 1, 실패 0).
- 이후 #95에서 이 두 알람(ECS CPU, RDS 연결)은 Grafana 규칙으로 옮기고 CloudWatch에서 지웠다.
