terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project}-${var.stage}"
  pacote_key = "deploy/observatorio.tar.gz"
  ami_id     = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.al2023[0].value
  subnet_id  = var.subnet_id != "" ? var.subnet_id : sort(data.aws_subnets.default[0].ids)[0]
}

# ---------------------------------------------------------------------------
# Rede: subnet pública da VPC padrão, sem nenhuma porta de entrada
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == "" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_vpc" "default" {
  count   = var.subnet_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

data "aws_subnet" "selecionada" {
  id = local.subnet_id
}

resource "aws_security_group" "runner" {
  name        = "${local.name}-runner"
  description = "Sem entrada; administracao pelo Session Manager"
  vpc_id      = data.aws_subnet.selecionada.vpc_id

  egress {
    description = "ANP, S3, SSM, imagens Docker"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Role da EC2: bucket do projeto + Session Manager
# ---------------------------------------------------------------------------

resource "aws_iam_role" "runner" {
  name                 = "${local.name}-runner"
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "bucket" {
  name = "bucket-projeto"
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Listar"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
      },
      {
        Sid    = "PipelineLeEGrava"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${var.bucket_arn}/bronze/*",
          "${var.bucket_arn}/resultados/*",
          "${var.bucket_arn}/logs/*",
        ]
      },
      {
        Sid    = "SoLeitura"
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = [
          "${var.bucket_arn}/deploy/*",
          "${var.bucket_arn}/config/*",
        ]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name = "${local.name}-runner"
  role = aws_iam_role.runner.name
}

# ---------------------------------------------------------------------------
# Código do projeto: a cada boot a instância baixa este pacote
# ---------------------------------------------------------------------------

resource "aws_s3_object" "pacote" {
  bucket = var.bucket_name
  key    = local.pacote_key
  source = var.pacote_path
  etag   = filemd5(var.pacote_path)
}

# ---------------------------------------------------------------------------
# Instância: liga, roda e desliga sozinha
# ---------------------------------------------------------------------------

resource "aws_instance" "runner" {
  ami                                  = local.ami_id
  instance_type                        = var.instance_type
  subnet_id                            = local.subnet_id
  vpc_security_group_ids               = [aws_security_group.runner.id]
  iam_instance_profile                 = aws_iam_instance_profile.runner.name
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "stop"

  # IMDSv2 obrigatório; hop limit 2 para os contêineres usarem a role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region          = data.aws_region.current.region
    bucket          = var.bucket_name
    pacote_key      = local.pacote_key
    compose_version = var.compose_version
    buildx_version  = var.buildx_version
  })

  tags = {
    Name = "${local.name}-runner"
  }

  # O user_data só roda no primeiro boot, e uma AMI nova recriaria a
  # instância (e o volume do Postgres). Mudanças nesses campos são ignoradas.
  # Desligada, a instância não tem IP público e a AWS devolve
  # associate_public_ip_address = false: sem ignorar, todo deploy com a
  # máquina parada a recriaria.
  lifecycle {
    ignore_changes = [ami, user_data, associate_public_ip_address]
  }

  depends_on = [aws_s3_object.pacote, aws_iam_role_policy.bucket]
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler: liga a instância a cada 10 dias
# ---------------------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name                 = "${local.name}-scheduler"
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "ligar-runner"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ec2:StartInstances"
      Resource = aws_instance.runner.arn
    }]
  })
}

resource "aws_scheduler_schedule" "ciclo" {
  name                = "${local.name}-ciclo"
  schedule_expression = var.schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.runner.id] })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
