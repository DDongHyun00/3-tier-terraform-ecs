package com.example.board.file.entity;

import jakarta.persistence.*;
import lombok.*;
import com.example.board.board.entity.Post;

@Entity
@Table(name = "files")
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor @Builder
public class FileEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String originalName;   // 원본 파일명
    private String savedName;      // 서버에 저장된 파일명

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "post_id", nullable = false)
    private Post post;
}
