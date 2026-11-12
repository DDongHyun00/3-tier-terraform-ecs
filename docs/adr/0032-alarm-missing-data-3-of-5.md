# DEC-32. ECS CPU와 RDS 연결 알람은 결측을 missing으로 두고 5분 중 3분으로 평가했다

- 상태: 확정 (두 알람은 이후 Grafana 규칙으로 옮겼다)
- 날짜: 2026-10-30

## 배경

2026-10-29 부하 시험에서 ECS 서비스 CPU가 6분 동안 93~98%였는데 `3tier-prod-ecs-cpu-high`(80% 초과, 60초 × 5번 중 5번, 결측은 notBreaching)가 울리지 않았다. 알람 이력을 보니 ECS 서비스 지표는 평가 시점보다 약 3분 50초 늦게 들어왔다(네 번 모두 3분 36초~3분 56초). 그 빈 구간을 notBreaching이 정상으로 채워서 "5번 모두 초과"가 성립할 수 없었다.

고려한 것:
- [AWS 권장 알람](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)의 ECS CPUUtilization 권장값은 Average, 80, 60초, 5번 중 5번이고 결측 처리는 기본값(missing)이다. 내 설정과 다른 건 결측 처리 하나였다.
- [CloudWatch 결측 처리 문서](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarms-and-missing-data.html)는 데이터가 늦거나 끊기는 지표에 M of N 평가를 쓰라고 한다.
- 같은 지표를 보는 목표 추적 알람(AWS가 만든 것, missing)은 정상으로 울렸다.

## 선택지

| 선택지 | 장점 | 단점 |
|---|---|---|
| 결측만 missing, 5번 중 5번 유지 | AWS 권장값 그대로다 | 한 분이라도 80% 밑이면 연속이 끊긴다 |
| 결측 missing과 5번 중 3번 | 지표가 한두 분 빠지거나 출렁여도 울린다 | 2분이 80% 밑인 톱니 모양 부하에도 울린다 |
| 5분 평균 1번 | 설정이 단순하다 | 짧고 센 폭주에 둔하다 |

세 안 모두 그날 부하는 잡는다. 그날 기록에 대입하면 첫째 안은 16:13, 둘째 안은 16:11에 울렸다. 차이는 울리는 시각과 출렁임에 버티는 정도였다.

## 결정

둘째 안을 골랐다. `3tier-prod-ecs-cpu-high`와 `3tier-prod-rds-connections-high`를 결측 missing(기본값), 5번 중 3번으로 바꿨다. 지표는 "연속 값은 missing, 건수는 notBreaching"으로 정리했다. ALB 5xx 비율은 건수 기반이라 notBreaching을 유지했고(이미 5번 중 3번), 비정상 타깃(2번 중 2번)과 RDS 여유 스토리지(1번)는 그대로 뒀다.

## 결과

- 2026-11-02 같은 200 RPS 부하에서 `ecs-cpu-high`가 01:25:15 KST에 ALARM이 됐고 SNS 전달도 성공했다. 과부하가 시작된 01:20부터 5분 15초였다.
- 품질 목표 "장애 탐지 5분 이내"에는 15초 모자랐다. 지표가 약 4분 늦게 들어오는 구조는 알람 설정으로 바꿀 수 없었다.
- 그래서 관제 VPC에 Prometheus와 Grafana를 두고 같은 부하로 다시 쟀다. Grafana는 4분 10초, CloudWatch는 6분 26초였다([monitoring.md](../monitoring.md)).
- 감수한 것: 톱니 모양 부하에도 울릴 수 있다. 오경보로 느껴지면 5번 중 4번으로 올리기로 했다.
- 지금은 이 두 알람을 Grafana 규칙으로 옮기고 CloudWatch에서 지웠다. CloudWatch에는 관제 서버가 죽어도 오는 비상 알람 2개와 오토스케일링이 쓰는 알람만 남겼다.
