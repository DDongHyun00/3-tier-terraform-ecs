package com.example.board.admin.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class DashboardStatsDto {
    private long totalPosts;
    private long todayPosts;
    private long totalComments;
    private long todayComments;
    private long totalLikes;
    private long todayLikes;
}