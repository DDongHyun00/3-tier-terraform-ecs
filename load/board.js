// 게시판 부하 테스트 (#40). 비로그인 GET 목록·상세를 섞어 오토스케일링(CPU 60% 목표, 2~4개)을 일으킨다.
// 실행법과 측정 항목은 load/README.md.
//
//   k6 run -e PROFILE=calibrate load/board.js            보정: 30→60→120→200 RPS 계단, 1분씩
//   k6 run -e PROFILE=main -e RATE=<RPS> --out csv=<파일> load/board.js   본 시험: 오르막 1분 + 유지 10분 + 내리막 1분
//   스케일 아웃 전·후 p95는 CSV를 경계 시각으로 나눠 load/p95.mjs로 집계한다(요약은 시험 전체 하나뿐이다)
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'https://3tier.link';
const PROFILE = __ENV.PROFILE || 'main';
const RATE = Number(__ENV.RATE || 100); // 본 시험 초당 요청 수. 보정 결과로 정한다
const HOLD = __ENV.HOLD || '10m';

const LIST_RATIO = 0.3; // 목록 3 : 상세 7
const LIST_PAGES = 10; // 시드 게시글 99개, 페이지당 10개
const POST_IDS = 99; // V2__seed.sql

// 초당 요청 수를 고정하는 열린 모델. 응답이 느려져도 부하가 줄지 않아 "늘어나야 버티는" 상황을 만든다
const scenarios = {
  calibrate: {
    executor: 'ramping-arrival-rate',
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: 50,
    maxVUs: 500,
    stages: [
      { target: 30, duration: '5s' },
      { target: 30, duration: '55s' },
      { target: 60, duration: '5s' },
      { target: 60, duration: '55s' },
      { target: 120, duration: '5s' },
      { target: 120, duration: '55s' },
      { target: 200, duration: '5s' },
      { target: 200, duration: '55s' },
    ],
  },
  main: {
    executor: 'ramping-arrival-rate',
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: 100,
    maxVUs: 500,
    stages: [
      { target: RATE, duration: '1m' },
      { target: RATE, duration: HOLD },
      { target: 0, duration: '1m' },
    ],
  },
};

if (!scenarios[PROFILE]) {
  throw new Error(`PROFILE은 calibrate 또는 main: ${PROFILE}`);
}

export const options = {
  scenarios: { [PROFILE]: scenarios[PROFILE] },

  // 상세 화면이 CSRF 토큰을 읽어 익명 요청마다 세션이 생기고, 세션은 RDS(SPRING_SESSION)에 저장된다.
  // k6 기본값은 반복마다 쿠키를 지워 요청마다 세션 INSERT가 생기므로, 가상 사용자를 재방문 사용자로 둔다
  noCookiesReset: true,

  // 화면별 p95가 요약에 나오도록 name 태그별 임계를 둔다
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
    'http_req_duration{name:list}': ['p(95)<1000'],
    'http_req_duration{name:detail}': ['p(95)<1000'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function randInt(min, max) {
  return min + Math.floor(Math.random() * (max - min + 1));
}

export default function () {
  let res;
  if (Math.random() < LIST_RATIO) {
    res = http.get(`${BASE_URL}/posts?page=${randInt(0, LIST_PAGES - 1)}`, { tags: { name: 'list' } });
  } else {
    // 조회수 +1(UPDATE)이 함께 일어나 DB 쓰기도 섞인다
    res = http.get(`${BASE_URL}/posts/${randInt(1, POST_IDS)}`, { tags: { name: 'detail' } });
  }
  check(res, { 'status 200': (r) => r.status === 200 });
}
