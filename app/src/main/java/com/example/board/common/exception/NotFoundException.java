package com.example.board.common.exception;

/**
 * URL로 가리킨 자원(글, 댓글, 파일)이 없을 때 던진다. GlobalExceptionHandler가 404로 바꾼다(#132).
 * 사용자 입력 오류라 5xx 알람에 잡히면 안 된다.
 */
public class NotFoundException extends RuntimeException {

    public NotFoundException(String message) {
        super(message);
    }
}
