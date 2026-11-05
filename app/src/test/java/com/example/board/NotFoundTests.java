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
 * 없는 글 번호로 들어오면 500이 아니라 404를 낸다(#132).
 * 사용자 입력 오류가 5xx 비율 알람을 울리지 않게 하려는 것이다. 실제 포트로 띄워 보안 필터까지 거친 응답을 본다.
 */
@Import(TestcontainersConfiguration.class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class NotFoundTests {

	@Value("${local.server.port}")
	int port;

	private final HttpClient http = HttpClient.newBuilder()
			.followRedirects(HttpClient.Redirect.NEVER)
			.build();

	private HttpResponse<String> get(String path, boolean ajax) throws Exception {
		HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).GET();
		if (ajax) {
			builder.header("X-Requested-With", "XMLHttpRequest");
		}
		return http.send(builder.build(), HttpResponse.BodyHandlers.ofString());
	}

	@Test
	void missingPostDetailReturns404Page() throws Exception {
		HttpResponse<String> response = get("/posts/99999", false);

		assertThat(response.statusCode()).isEqualTo(404);
		assertThat(response.body()).contains("404");
	}

	@Test
	void missingPostDetailReturns404JsonForAjax() throws Exception {
		HttpResponse<String> response = get("/posts/99999", true);

		assertThat(response.statusCode()).isEqualTo(404);
		assertThat(response.body()).contains("\"status\":404").contains("게시글을 찾을 수 없습니다.");
	}

	@Test
	void existingListStillReturns200() throws Exception {
		assertThat(get("/posts", false).statusCode()).isEqualTo(200);
	}
}
