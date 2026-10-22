output "function_name" {
  value = aws_lambda_function.api.function_name
}

output "function_url" {
  value = aws_lambda_function_url.api.function_url
}

output "origem_ssm_parameter" {
  value = aws_ssm_parameter.origem.name
}
