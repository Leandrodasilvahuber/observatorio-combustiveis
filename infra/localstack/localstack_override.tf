# Override aplicado apenas no ambiente local (o Makefile copia este arquivo
# para infra/envs/<env>/ e o remove antes de qualquer comando contra a AWS).
# Redireciona o provider para o LocalStack e usa um state separado.

terraform {
  backend "local" {
    path = "terraform.localstack.tfstate"
  }
}

provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    budgets   = "http://localhost:4566"
    ec2       = "http://localhost:4566"
    iam       = "http://localhost:4566"
    lambda    = "http://localhost:4566"
    logs      = "http://localhost:4566"
    s3        = "http://localhost:4566"
    s3control = "http://localhost:4566"
    scheduler = "http://localhost:4566"
    ssm       = "http://localhost:4566"
    sts       = "http://localhost:4566"
  }
}
