output "dashboard_name" {
  description = "콘솔 CloudWatch > 대시보드에서 찾는 이름"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
