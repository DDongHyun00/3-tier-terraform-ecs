package com.example.board;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * /actuator/prometheus가 인증 없이 Prometheus 형식으로 JVM·HTTP·Hikari 지표를 내는지(E11 #94).
 * 실제 포트로 띄워 보안 필터까지 거친 응답을 본다.
 */
@Import(TestcontainersConfiguration.class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ActuatorPrometheusTests {

	@Value("${local.server.port}")
	int port;

	private final HttpClient http = HttpClient.newBuilder()
			.followRedirects(HttpClient.Redirect.NEVER)
			.build();

	private HttpResponse<String> get(String path) throws Exception {
		HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).GET().build();
		return http.send(request, HttpResponse.BodyHandlers.ofString());
	}

	private HttpResponse<String> getViaProxy(String path) throws Exception {
		// ALB를 거친 요청처럼 X-Forwarded-For를 붙인다
		HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
				.header("X-Forwarded-For", "203.0.113.10")
				.GET().build();
		return http.send(request, HttpResponse.BodyHandlers.ofString());
	}

	@Test
	void prometheusEndpointExposesJvmHttpAndHikariMetrics() throws Exception {
		// http_server_requests를 만들려고 공개 경로를 먼저 한 번 부른다
		assertThat(get("/actuator/health").statusCode()).isEqualTo(200);

		HttpResponse<String> response = get("/actuator/prometheus");

		assertThat(response.statusCode()).isEqualTo(200);
		assertThat(response.body())
				.contains("jvm_memory_used_bytes")
				.contains("http_server_requests_seconds_bucket")
				.contains("hikaricp_connections_active")
				.contains("application=\"board\"");
	}

	@Test
	void prometheusEndpointRejectsRequestsThatCameThroughTheLoadBalancer() throws Exception {
		HttpResponse<String> response = getViaProxy("/actuator/prometheus");

		assertThat(response.statusCode()).isNotEqualTo(200);
		assertThat(response.body()).doesNotContain("jvm_memory_used_bytes");
	}

	@Test
	void otherActuatorEndpointsStayHidden() throws Exception {
		// 노출 목록(health, prometheus) 밖이라 엔드포인트가 없고, 보안 설정상 비로그인 요청은 로그인으로 돌려보낸다
		assertThat(get("/actuator/env").statusCode()).isNotEqualTo(200);
	}
}
