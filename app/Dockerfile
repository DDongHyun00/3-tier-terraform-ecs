# syntax=docker/dockerfile:1

# ---------- 1단계: 빌드 ----------
FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /workspace

# 의존성 레이어를 먼저 만들어 소스만 바뀔 때 재다운로드를 피한다
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon -q

# 테스트는 Docker(Testcontainers)가 필요하므로 이미지 빌드에서는 제외하고 CI에서 따로 돌린다
COPY src ./src
RUN ./gradlew bootJar --no-daemon -q -x test

# 레이어 분리: dependencies(lib/*.jar) / snapshot-dependencies / application(app.jar)
# --launcher 없이 추출하므로 실행은 java -jar app.jar (app.jar의 Class-Path가 lib/를 가리킨다)
RUN cp build/libs/*-SNAPSHOT.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination extracted

# ---------- 2단계: 실행 ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

RUN adduser -S -u 1001 -h /app app
USER app

# 자주 바뀌지 않는 레이어부터 복사해 캐시 적중률을 높인다
COPY --from=builder --chown=app:app /workspace/extracted/dependencies/ ./
COPY --from=builder --chown=app:app /workspace/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=app:app /workspace/extracted/application/ ./

# 컨테이너 메모리 한도 기준으로 힙을 잡는다 (ECS 태스크 메모리의 75%)
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
