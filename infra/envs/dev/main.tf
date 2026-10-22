terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # State na AWS, compartilhado entre a máquina local e o GitHub Actions. O
  # bucket é criado por infra/bootstrap. No LocalStack o override troca por
  # backend "local".
  # O bucket (observatorio-tfstate-<conta>) vem no init:
  #   terraform init -backend-config="bucket=observatorio-tfstate-<conta>"
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Mesmo provider para LocalStack e AWS: localmente o Makefile copia
# infra/localstack/localstack_override.tf, que aponta para localhost:4566.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.stage
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Política-limite criada pelo infra/bootstrap: o papel de deploy só cria e
# altera papéis que a carregam.
locals {
  limite_papeis = var.usar_limite_papeis ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-${var.stage}-limite-papeis" : null
}

module "storage" {
  source = "../../modules/storage"

  project       = var.project
  stage         = var.stage
  force_destroy = true
}

module "api" {
  source = "../../modules/api"

  project      = var.project
  stage        = var.stage
  source_dir   = "${path.root}/../../../api"
  bucket_name  = module.storage.bucket_name
  bucket_arn   = module.storage.bucket_arn
  url_id_local = var.api_url_id_local

  base_path                   = var.api_base_path
  url_auth_type               = var.api_url_auth_type
  cloudfront_distribution_arn = var.cloudfront_distribution_arn
  reserved_concurrency        = var.api_reserved_concurrency
  permissions_boundary        = local.limite_papeis
}

module "runner" {
  source = "../../modules/runner"

  project     = var.project
  stage       = var.stage
  bucket_name = module.storage.bucket_name
  bucket_arn  = module.storage.bucket_arn
  pacote_path = "${path.root}/build/observatorio.tar.gz"
  ami_id      = var.ami_id

  permissions_boundary = local.limite_papeis
}

# Alerta de custo (documento: US$ 10/mês). Só é criado com e-mail definido.
resource "aws_budgets_budget" "mensal" {
  count = var.email_alertas != "" ? 1 : 0

  name         = "${var.project}-${var.stage}-mensal"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email_alertas]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.email_alertas]
  }
}
