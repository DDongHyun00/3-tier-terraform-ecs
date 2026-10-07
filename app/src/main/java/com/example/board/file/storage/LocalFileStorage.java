package com.example.board.file.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.UUID;

/** 디스크 저장소. 컨테이너 안에 저장되므로 운영(태스크 여러 개, 재배포)에서는 쓰지 않는다. */
@Slf4j
@Component
@ConditionalOnProperty(name = "app.storage.type", havingValue = "local", matchIfMissing = true)
public class LocalFileStorage implements FileStorage {

    private final Path root;

    public LocalFileStorage(@Value("${app.storage.local.dir:uploads}") String dir) {
        this.root = Paths.get(dir).toAbsolutePath().normalize();
        log.info("첨부파일 저장소: local dir={}", root);
    }

    @Override
    public String store(MultipartFile file) throws IOException {
        String savedName = UUID.randomUUID() + "_" + file.getOriginalFilename();
        Path target = root.resolve(savedName);
        Files.createDirectories(root);
        file.transferTo(target);
        return savedName;
    }

    @Override
    public Resource load(String savedName) {
        try {
            Resource resource = new UrlResource(root.resolve(savedName).toUri());
            if (!resource.exists() || !resource.isReadable()) {
                throw new IllegalArgumentException("파일을 읽을 수 없습니다.");
            }
            return resource;
        } catch (IOException e) {
            throw new IllegalArgumentException("파일을 읽을 수 없습니다.", e);
        }
    }
}
