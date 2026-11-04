package com.example.board.logging;

import java.io.IOException;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 요청마다 접근 로그 한 줄을 남긴다(E12 #99). 필드 이름은 Elastic Common Schema(ECS)를 따른다.
 * 로그 출력 형식은 application.properties의 구조화 로그(ECS JSON)라서 Kibana에서 http.response.status_code:500처럼 필드로 검색된다.
 *
 * 요청 ID는 ALB가 붙이는 X-Amzn-Trace-Id를 쓰고, 없으면(로컬·직접 호출) 새로 만든다.
 * MDC에 넣어 두면 같은 요청 안에서 남긴 다른 로그(예외 등)에도 같은 ID가 붙는다.
 * 헬스체크·지표 수집(/actuator)은 15초마다 와서 로그만 늘리므로 남기지 않는다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestLogFilter extends OncePerRequestFilter {

	static final String REQUEST_ID_MDC_KEY = "http.request.id";
	static final String TRACE_HEADER = "X-Amzn-Trace-Id";

	private static final Logger log = LoggerFactory.getLogger(RequestLogFilter.class);

	@Override
	protected boolean shouldNotFilter(HttpServletRequest request) {
		return request.getRequestURI().startsWith("/actuator");
	}

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
			throws ServletException, IOException {
		String requestId = request.getHeader(TRACE_HEADER);
		if (requestId == null || requestId.isBlank()) {
			requestId = UUID.randomUUID().toString();
		}
		MDC.put(REQUEST_ID_MDC_KEY, requestId);
		long start = System.nanoTime();
		Throwable failure = null;
		try {
			chain.doFilter(request, response);
		}
		catch (IOException | ServletException | RuntimeException ex) {
			failure = ex;
			throw ex;
		}
		finally {
			long durationMs = (System.nanoTime() - start) / 1_000_000;
			// 예외가 컨테이너까지 올라가면 응답 코드가 아직 200일 수 있어 500으로 남긴다
			int status = (failure != null && response.getStatus() < 400) ? 500 : response.getStatus();
			log.atInfo()
					.addKeyValue("http.request.method", request.getMethod())
					.addKeyValue("url.path", request.getRequestURI())
					.addKeyValue("http.response.status_code", status)
					.addKeyValue("event.duration_ms", durationMs)
					.log("{} {} {} {}ms", request.getMethod(), request.getRequestURI(), status, durationMs);
			MDC.remove(REQUEST_ID_MDC_KEY);
		}
	}

}
