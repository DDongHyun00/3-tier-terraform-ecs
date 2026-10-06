package com.example.board.admin.controller;

import lombok.RequiredArgsConstructor;
import com.example.board.admin.service.DashboardService;
import com.example.board.admin.dto.DashboardStatsDto;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
@RequiredArgsConstructor
@RequestMapping("/admin")
public class AdminDashboardController {

    private final DashboardService dashboardService;

    @GetMapping("/dashboard")
    public String dashboard(Model model) {
        DashboardStatsDto stats = dashboardService.getStats();
        model.addAttribute("stats", stats);
        return "admin/dashboard"; // templates/admin/dashboard.html
    }
}
