package com.example.board.file.controller;

import com.example.board.common.exception.NotFoundException;
import lombok.RequiredArgsConstructor;
import com.example.board.file.entity.FileEntity;
import com.example.board.file.repository.FileRepository;
import com.example.board.file.storage.FileStorage;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

@Controller
@RequiredArgsConstructor
public class FileController {

    private final FileRepository fileRepository;
    private final FileStorage fileStorage;

    @GetMapping("/files/{id}/download")
    public ResponseEntity<Resource> downloadFile(@PathVariable Long id) throws Exception {
        FileEntity file = fileRepository.findById(id)
                .orElseThrow(() -> new NotFoundException("파일을 찾을 수 없습니다."));

        Resource resource = fileStorage.load(file.getSavedName());

        String encodedName = URLEncoder.encode(file.getOriginalName(), StandardCharsets.UTF_8)
                .replace("+", "%20"); // 공백 처리

        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + encodedName + "\"")
                .body(resource);
    }
}
