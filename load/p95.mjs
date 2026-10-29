// k6 CSV 결과(--out csv)를 시각 경계로 나눠 구간별 응답 시간 백분위를 낸다 (#40).
// k6 요약(--summary-export)은 시험 전체 하나만 주므로, 스케일 아웃 전·후 p95는 원시 결과에서 다시 집계한다.
//
//   node load/p95.mjs <k6 결과.csv> [경계 시각 ...]
//   예) node load/p95.mjs local/captures/E7/k6-main.csv 2026-10-30T14:05:10+09:00 2026-10-30T14:07:40+09:00
//       → 시작~경계1, 경계1~경계2, 경계2~끝 세 구간. 경계는 스케일링 활동 시각, 새 타깃 healthy 시각 등
//
// 집계 대상: http_req_duration(ms). 실패 요청도 포함한다(k6 요약의 http_req_duration과 같은 기준).
// 백분위: 정렬 후 선형 보간. k6 요약과 소수점 아래가 조금 다를 수 있다.
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';

const [file, ...boundaryArgs] = process.argv.slice(2);
if (!file) {
  console.error('사용법: node load/p95.mjs <k6 결과.csv> [경계 시각(ISO 8601) ...]');
  process.exit(1);
}

const boundaries = boundaryArgs.map((s) => {
  const t = Date.parse(s) / 1000;
  if (Number.isNaN(t)) {
    console.error(`시각을 읽지 못함: ${s}`);
    process.exit(1);
  }
  return t;
});
boundaries.sort((a, b) => a - b);

// 구간 번호 → { all: [], list: [], detail: [], first, last }
const segments = boundaries.map(() => null).concat(null).map(() => ({ all: [], byName: {}, first: Infinity, last: -Infinity }));

function segmentOf(ts) {
  let i = 0;
  while (i < boundaries.length && ts >= boundaries[i]) i++;
  return i;
}

function percentile(sorted, p) {
  if (sorted.length === 0) return NaN;
  const idx = (p / 100) * (sorted.length - 1);
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}

function fmtTime(ts) {
  return Number.isFinite(ts) ? new Date(ts * 1000).toISOString() : '-';
}

const rl = createInterface({ input: createReadStream(file), crlfDelay: Infinity });
let col = null;

for await (const line of rl) {
  if (!line) continue;
  const cells = line.split(',');
  if (!col) {
    // 첫 줄은 헤더. 열 위치는 k6 버전에 따라 달라질 수 있어 이름으로 찾는다
    col = Object.fromEntries(cells.map((name, i) => [name, i]));
    for (const need of ['metric_name', 'timestamp', 'metric_value', 'name']) {
      if (!(need in col)) {
        console.error(`CSV 헤더에 ${need} 열이 없다. k6 run --out csv=<파일>로 만든 파일인지 확인`);
        process.exit(1);
      }
    }
    continue;
  }
  if (cells[col.metric_name] !== 'http_req_duration') continue;

  const ts = Number(cells[col.timestamp]);
  const ms = Number(cells[col.metric_value]);
  const name = cells[col.name] || '(이름 없음)';
  const seg = segments[segmentOf(ts)];
  seg.all.push(ms);
  (seg.byName[name] ||= []).push(ms);
  seg.first = Math.min(seg.first, ts);
  seg.last = Math.max(seg.last, ts);
}

if (!col) {
  console.error('빈 파일');
  process.exit(1);
}

const rows = [];
segments.forEach((seg, i) => {
  const series = [['전체', seg.all], ...Object.entries(seg.byName).sort()];
  for (const [label, values] of series) {
    values.sort((a, b) => a - b);
    rows.push({
      구간: i + 1,
      시작: fmtTime(seg.first),
      끝: fmtTime(seg.last),
      화면: label,
      요청: values.length,
      'p50(ms)': Math.round(percentile(values, 50)),
      'p95(ms)': Math.round(percentile(values, 95)),
      'p99(ms)': Math.round(percentile(values, 99)),
    });
  }
});
console.table(rows);
