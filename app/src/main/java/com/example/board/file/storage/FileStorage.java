package com.example.board.file.storage;

import org.springframework.core.io.Resource;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

/**
 * 첨부파일 저장소. 구현은 설정 {@code app.storage.type}으로 고른다.
 * <ul>
 *   <li>{@code local}: 디스크 (로컬 개발, 테스트)</li>
 *   <li>{@code s3}: Amazon S3 (운영. ECS 태스크 역할로 인증, 액세스 키 없음)</li>
 * </ul>
 */
public interface FileStorage {

    /** 파일을 저장하고 저장소 안의 식별자(savedName)를 돌려준다. */
    String store(MultipartFile file) throws IOException;

    /** savedName으로 파일을 읽는다. 없으면 {@link IllegalArgumentException}. */
    Resource load(String savedName);
}
