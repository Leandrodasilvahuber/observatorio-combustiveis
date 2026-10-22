# Bootstrap: o que precisa existir antes do primeiro deploy pelo GitHub Actions.
#   - bucket do state remoto do Terraform (infra/envs/*)
#   - papel que o GitHub Actions assume via OIDC para fazer o deploy
# Roda uma vez, da máquina local, com uma credencial administrativa:
#   terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply
# O state dele também fica no bucket (chave bootstrap/), migrado após a criação.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # O bucket (observatorio-tfstate-<conta>) vem no init:
  #   terraform init -backend-config="bucket=observatorio-tfstate-<conta>"
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  conta   = data.aws_caller_identity.current.account_id
  prefixo = "${var.project}-${var.stage}"
}

# ---------------------------------------------------------------------------
# State remoto
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project}-tfstate-${local.conta}"
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versões antigas do state somem depois de 90 dias.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "versoes-antigas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# Papel do GitHub Actions (OIDC). O provedor token.actions.githubusercontent.com
# já existe na conta (criado por outro projeto), então só é lido.
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Nome fora do prefixo observatorio-dev-*: o deploy não consegue alterar o
# próprio papel.
resource "aws_iam_role" "deploy" {
  name                 = "github-deploy-${var.project}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Só o job no ambiente "producao" deste repositório, que no GitHub
          # aceita apenas a branch main
          "token.actions.githubusercontent.com:sub" = "${var.github_sub_prefixo}:environment:producao"
        }
      }
    }]
  })
}

# Permissões só sobre os recursos do projeto (nomes observatorio-dev*). A EC2
# não aceita bem restrição por nome na criação, então fica por tag/serviço.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-${local.prefixo}"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateRemoto"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/dev/*",
        ]
      },
      {
        Sid      = "BucketDoProjeto"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = ["arn:aws:s3:::${local.prefixo}-*", "arn:aws:s3:::${local.prefixo}-*/*"]
      },
      {
        Sid      = "Lambda"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:${var.region}:${local.conta}:function:${local.prefixo}-*"
      },
      {
        Sid      = "LambdaLeitura"
        Effect   = "Allow"
        Action   = ["lambda:GetAccountSettings", "lambda:ListFunctions"]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = "logs:*"
        Resource = [
          "arn:aws:logs:${var.region}:${local.conta}:log-group:/aws/lambda/${local.prefixo}-*",
          "arn:aws:logs:${var.region}:${local.conta}:log-group:/aws/lambda/${local.prefixo}-*:*",
        ]
      },
      {
        Sid      = "LogsLeitura"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "logs:ListTagsForResource"]
        Resource = "*"
      },
      {
        Sid    = "PapeisDoProjeto"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile", "iam:UntagInstanceProfile", "iam:ListInstanceProfileTags",
        ]
        Resource = [
          "arn:aws:iam::${local.conta}:role/${local.prefixo}-*",
          "arn:aws:iam::${local.conta}:instance-profile/${local.prefixo}-*",
        ]
      },
      {
        # Políticas gerenciadas: só as duas que o projeto usa.
        Sid      = "PoliticasGerenciadas"
        Effect   = "Allow"
        Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource = "arn:aws:iam::${local.conta}:role/${local.prefixo}-*"
        Condition = {
          ArnEquals = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
              "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
            ]
          }
        }
      },
      {
        # A EC2 não restringe bem por nome na criação (instância, SG, volume,
        # interface de rede); a conta não tem outras instâncias.
        Sid      = "EC2"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },
      {
        Sid      = "Agendamento"
        Effect   = "Allow"
        Action   = "scheduler:*"
        Resource = "arn:aws:scheduler:${var.region}:${local.conta}:schedule/default/${local.prefixo}-*"
      },
      {
        Sid    = "ParametrosSSM"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter", "ssm:GetParameter", "ssm:GetParameters", "ssm:DeleteParameter",
          "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource",
        ]
        Resource = "arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/${var.stage}/*"
      },
      {
        # AMI mais recente do Amazon Linux 2023 (parâmetro público da AWS)
        Sid      = "AmiPublica"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/*"
      },
      {
        Sid      = "SSMLeitura"
        Effect   = "Allow"
        Action   = "ssm:DescribeParameters"
        Resource = "*"
      },
    ]
  })
}
