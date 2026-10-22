output "instance_id" {
  value = aws_instance.runner.id
}

output "schedule_name" {
  value = aws_scheduler_schedule.ciclo.name
}
