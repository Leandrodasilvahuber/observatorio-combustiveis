terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.stage}"
}

# Bucket único do projeto, separado por prefixos:
#   bronze/anp/execucao=DATA/  CSVs originais da ANP (nunca alterados)
#   resultados/                JSON por período + latest.json
#   logs/                      logs de cada execução
# Nomes de bucket são globais na AWS; o account id evita colisão.
resource "aws_s3_bucket" "dados" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "dados" {
  bucket                  = aws_s3_bucket.dados.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dados" {
  bucket = aws_s3_bucket.dados.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "dados" {
  bucket = aws_s3_bucket.dados.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dados" {
  bucket = aws_s3_bucket.dados.id

  rule {
    id     = "expira-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = var.logs_retention_days
    }
  }

  rule {
    id     = "limpa-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
