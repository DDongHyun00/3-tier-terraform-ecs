package com.example.board.file.repository;

import com.example.board.file.entity.FileEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FileRepository extends JpaRepository<FileEntity, Long> {
    List<FileEntity> findByPost_PostId(Long postId);
}
