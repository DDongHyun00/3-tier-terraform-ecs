package com.example.board.file.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.util.UUID;

/**
 * Amazon S3 저장소. 자격 증명과 리전은 SDK 기본 체인을 따른다.
 * ECS에서는 태스크 역할(IAM Role)과 AWS_REGION 환경 변수로 해결되므로 액세스 키를 넣지 않는다.
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "app.storage.type", havingValue = "s3")
public class S3FileStorage implements FileStorage {

    private final S3Client s3;
    private final String bucket;

    public S3FileStorage(@Value("${app.storage.s3.bucket}") String bucket) {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException("app.storage.type=s3 이면 app.storage.s3.bucket(S3_BUCKET)이 필요합니다.");
        }
        this.bucket = bucket;
        this.s3 = S3Client.create();
        log.info("첨부파일 저장소: s3 bucket={} region={}", bucket, s3.serviceClientConfiguration().region());
    }

    @Override
    public String store(MultipartFile file) throws IOException {
        String savedName = UUID.randomUUID() + "_" + file.getOriginalFilename();
        PutObjectRequest request = PutObjectRequest.builder()
                .bucket(bucket)
                .key(savedName)
                .contentType(file.getContentType())
                .contentLength(file.getSize())
                .build();
        s3.putObject(request, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));
        return savedName;
    }

    @Override
    public Resource load(String savedName) {
        try {
            GetObjectRequest request = GetObjectRequest.builder().bucket(bucket).key(savedName).build();
            return new InputStreamResource(s3.getObject(request));
        } catch (NoSuchKeyException e) {
            throw new IllegalArgumentException("파일을 읽을 수 없습니다.", e);
        }
    }
}
