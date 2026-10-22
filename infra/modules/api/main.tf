terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  name = "${var.project}-${var.stage}-api"
}

# O código da Lambda só muda via Terraform: o pipeline grava JSON no S3 e não
# tem permissão para alterar funções. O pacote leva a pasta api/ inteira
# (handler e contornos do mapa).
data "archive_file" "api" {
  type        = "zip"
  source_dir  = var.source_dir
  excludes    = ["__pycache__", "__pycache__/*"]
  output_path = "${path.root}/build/api.zip"
}

resource "aws_iam_role" "api" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Leitura apenas do prefixo de resultados. Sem ListBucket, um período
# inexistente chega como AccessDenied, que o handler trata como 404.
resource "aws_iam_role_policy" "resultados" {
  name = "leitura-resultados"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${var.bucket_arn}/${var.prefixo_resultados}/*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "api" {
  function_name                  = local.name
  role                           = aws_iam_role.api.arn
  runtime                        = "python3.12"
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.api.output_path
  source_code_hash               = data.archive_file.api.output_base64sha256
  memory_size                    = 128
  timeout                        = 10
  reserved_concurrent_executions = var.reserved_concurrency
  tags                           = var.url_id_local != "" ? { _custom_id_ = var.url_id_local } : {}

  environment {
    variables = {
      BUCKET_NAME        = var.bucket_name
      PREFIXO_RESULTADOS = var.prefixo_resultados
      BASE_PATH          = var.base_path
    }
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy_attachment.logs]
}

# CORS é devolvido pelo próprio handler, igual no LocalStack e na AWS.
# Na AWS a URL exige assinatura (AWS_IAM) e só a CloudFront do site chama, via
# OAC; no LocalStack fica pública (NONE).
resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = var.url_auth_type
}

# URL pública exige as duas permissões (InvokeFunctionUrl e InvokeFunction
# restrita a chamadas pela URL).
resource "aws_lambda_permission" "url_publica" {
  count = var.url_auth_type == "NONE" ? 1 : 0

  statement_id           = "FunctionUrlPublica"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke_via_url" {
  count = var.url_auth_type == "NONE" ? 1 : 0

  statement_id             = "InvokeViaFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api.function_name
  principal                = "*"
  invoked_via_function_url = true
}

# Atrás da CloudFront (OAC): também são duas permissões, presas à distribuição.
resource "aws_lambda_permission" "cloudfront_url" {
  count = var.cloudfront_distribution_arn != "" ? 1 : 0

  statement_id           = "CloudFrontFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = var.cloudfront_distribution_arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  count = var.cloudfront_distribution_arn != "" ? 1 : 0

  statement_id  = "CloudFrontInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = var.cloudfront_distribution_arn
}

# Domínio da Function URL para quem monta a CloudFront (o stack do site, em
# outro repositório, lê este parâmetro). Muda só se a função for recriada.
resource "aws_ssm_parameter" "origem" {
  name  = "/${var.project}/${var.stage}/api-origem"
  type  = "String"
  value = split("/", aws_lambda_function_url.api.function_url)[2]
}

# As permissões públicas ganharam count; sem isto o Terraform as recriaria.
moved {
  from = aws_lambda_permission.url_publica
  to   = aws_lambda_permission.url_publica[0]
}

moved {
  from = aws_lambda_permission.invoke_via_url
  to   = aws_lambda_permission.invoke_via_url[0]
}
