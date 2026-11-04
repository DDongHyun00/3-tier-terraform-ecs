package com.example.board.logging;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.slf4j.event.KeyValuePair;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 요청 로그 필터(E12 #99): 필드(메서드·경로·상태 코드·소요 시간)와 요청 ID가 붙는지, /actuator는 빼는지.
 * DB·컨테이너 없이 필터만 돌린다.
 */
class RequestLogFilterTests {

	private final RequestLogFilter filter = new RequestLogFilter();
	private final Logger logger = (Logger) LoggerFactory.getLogger(RequestLogFilter.class);
	private ListAppender<ILoggingEvent> appender;

	@BeforeEach
	void attach() {
		appender = new ListAppender<>();
		appender.start();
		logger.addAppender(appender);
	}

	@AfterEach
	void detach() {
		logger.detachAppender(appender);
	}

	private static Map<String, Object> fields(ILoggingEvent event) {
		List<KeyValuePair> pairs = event.getKeyValuePairs();
		return pairs.stream().collect(Collectors.toMap(p -> p.key, p -> p.value));
	}

	@Test
	void logsFieldsAndAlbTraceId() throws Exception {
		MockHttpServletRequest request = new MockHttpServletRequest("GET", "/posts/1");
		request.addHeader(RequestLogFilter.TRACE_HEADER, "Root=1-abc-def");
		MockHttpServletResponse response = new MockHttpServletResponse();
		String[] idSeenInsideRequest = new String[1];

		filter.doFilter(request, response, (req, res) -> {
			idSeenInsideRequest[0] = MDC.get(RequestLogFilter.REQUEST_ID_MDC_KEY);
			((MockHttpServletResponse) res).setStatus(404);
		});

		assertThat(idSeenInsideRequest[0]).isEqualTo("Root=1-abc-def");
		assertThat(appender.list).hasSize(1);
		ILoggingEvent event = appender.list.get(0);
		assertThat(fields(event))
				.containsEntry("http.request.method", "GET")
				.containsEntry("url.path", "/posts/1")
				.containsEntry("http.response.status_code", 404)
				.containsKey("event.duration_ms");
		assertThat(event.getMDCPropertyMap()).containsEntry(RequestLogFilter.REQUEST_ID_MDC_KEY, "Root=1-abc-def");
		assertThat(MDC.get(RequestLogFilter.REQUEST_ID_MDC_KEY)).isNull();
	}

	@Test
	void generatesIdWhenNoTraceHeader() throws Exception {
		MockHttpServletRequest request = new MockHttpServletRequest("POST", "/posts");

		filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> { });

		assertThat(appender.list.get(0).getMDCPropertyMap().get(RequestLogFilter.REQUEST_ID_MDC_KEY)).isNotBlank();
	}

	@Test
	void logsUncaughtExceptionAs500() {
		MockHttpServletRequest request = new MockHttpServletRequest("GET", "/posts");

		assertThatThrownBy(() -> filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> {
			throw new IllegalStateException("db down");
		})).isInstanceOf(IllegalStateException.class);

		assertThat(fields(appender.list.get(0))).containsEntry("http.response.status_code", 500);
	}

	@Test
	void skipsActuator() throws Exception {
		MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health/liveness");
		request.setRequestURI("/actuator/health/liveness");

		filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> { });

		assertThat(appender.list).isEmpty();
	}

}
