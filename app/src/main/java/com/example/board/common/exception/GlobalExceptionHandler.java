package com.example.board.common.exception;

import jakarta.servlet.http.HttpServletRequest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.async.AsyncRequestTimeoutException;
import org.springframework.web.servlet.ModelAndView;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.*;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

//    Ajax 요청인지 판별
    private boolean isAjax(HttpServletRequest request) {
        String xhr = request.getHeader("X-Requested-With");
        return "XMLHttpRequest".equalsIgnoreCase(xhr);
    }

//    JSON 응답 생성
    private ResponseEntity<Map<String, Object>> json(HttpStatus status, String message) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", status.value());
        body.put("error", status.getReasonPhrase());
        body.put("message", message);
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_JSON)
                .body(body);
    }

//    뷰 응답 생성
    private ModelAndView view(String template, HttpStatus status, String message) {
        ModelAndView mv = new ModelAndView(template);
        mv.setStatus(status);
        mv.addObject("status", status.value());
        mv.addObject("message", message);
        return mv;
    }
//    404: 정적 리소스 및 매핑 없음 (Spring Boot 4)
    @ExceptionHandler(NoResourceFoundException.class)
    public Object handle404(NoResourceFoundException ex, HttpServletRequest request) {
        log.warn("404 Not Found: {}", ex.getResourcePath());
        String msg = "요청하신 페이지가 존재하지 않습니다.";
        return isAjax(request) ? json(HttpStatus.NOT_FOUND, msg)
                : view("error/404", HttpStatus.NOT_FOUND, msg);
    }

//    404: URL로 가리킨 글·댓글·파일이 없음 (#132). 사용자 입력 오류라 error가 아닌 warn
    @ExceptionHandler(NotFoundException.class)
    public Object handleNotFound(NotFoundException ex, HttpServletRequest request) {
        log.warn("404 Not Found: {} {}", request.getRequestURI(), ex.getMessage());
        String msg = ex.getMessage();
        return isAjax(request) ? json(HttpStatus.NOT_FOUND, msg)
                : view("error/404", HttpStatus.NOT_FOUND, msg);
    }

//    403: 남의 글·댓글을 수정·삭제하려 함. 사용자 요청 오류라 error가 아닌 warn (5xx 알람에 잡히면 안 된다)
    @ExceptionHandler(ForbiddenException.class)
    public Object handleForbidden(ForbiddenException ex, HttpServletRequest request) {
        log.warn("403 Forbidden: {} {}", request.getRequestURI(), ex.getMessage());
        String msg = ex.getMessage();
        return isAjax(request) ? json(HttpStatus.FORBIDDEN, msg)
                : view("error/403", HttpStatus.FORBIDDEN, msg);
    }

//    403: 권한 없음
    @ExceptionHandler(AccessDeniedException.class)
    public Object handle403(AccessDeniedException ex, HttpServletRequest request) {
        log.warn("403 Forbidden: {}", ex.getMessage());
        String msg = "접근 권한이 없습니다.";
        return isAjax(request) ? json(HttpStatus.FORBIDDEN, msg)
                : view("error/403", HttpStatus.FORBIDDEN, msg);
    }

//    400: DTO 검증 실패
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Object handle400(MethodArgumentNotValidException ex, HttpServletRequest request) {
        FieldError fe = ex.getBindingResult().getFieldError();
        String msg = (fe != null) ? fe.getDefaultMessage() : "요청 값이 올바르지 않습니다.";
        log.debug("400 Bad Request: {}", msg);
        return isAjax(request) ? json(HttpStatus.BAD_REQUEST, msg)
                : view("error/error", HttpStatus.BAD_REQUEST, msg);
    }

//    SSE 연결 타임아웃 (정상적인 동작)
    @ExceptionHandler(AsyncRequestTimeoutException.class)
    public void handleAsyncTimeout(AsyncRequestTimeoutException ex, HttpServletRequest request) {
        // SSE 연결 타임아웃은 정상적인 동작이므로 로그만 출력하고 에러로 처리하지 않음
        log.debug("SSE 연결 타임아웃: {}", request.getRequestURI());
    }

//    500: 기타 모든 예외
    @ExceptionHandler(Exception.class)
    public Object handle500(Exception ex, HttpServletRequest request) {
        log.error("500 Internal Server Error", ex);
        String msg = "요청 처리 중 서버 오류가 발생했습니다.";
        return isAjax(request) ? json(HttpStatus.INTERNAL_SERVER_ERROR, msg)
                : view("error/500", HttpStatus.INTERNAL_SERVER_ERROR, msg);
    }
}
