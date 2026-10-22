output "deploy_role_arn" {
  description = "Vai na variável AWS_DEPLOY_ROLE_ARN do repositório no GitHub"
  value       = aws_iam_role.deploy.arn
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "limite_papeis_arn" {
  description = "Permissions boundary dos papéis observatorio-dev-*"
  value       = aws_iam_policy.limite_papeis.arn
}
