output "bucket_name" {
  value = module.storage.bucket_name
}

output "api_url" {
  value = module.api.function_url
}

output "instance_id" {
  value = module.runner.instance_id
}

output "api_origem_ssm_parameter" {
  value = module.api.origem_ssm_parameter
}
