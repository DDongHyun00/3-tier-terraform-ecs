package com.example.board.common.exception;

/**
 * 로그인은 했지만 남의 글·댓글을 수정하거나 삭제하려 할 때 던진다. GlobalExceptionHandler가 403으로 바꾼다.
 * 사용자 요청 오류라 5xx 알람에 잡히면 안 된다.
 */
public class ForbiddenException extends RuntimeException {

    public ForbiddenException(String message) {
        super(message);
    }
}
