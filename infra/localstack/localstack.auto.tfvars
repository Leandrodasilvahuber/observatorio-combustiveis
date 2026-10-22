# Copiado para infra/envs/<env>/ pelo `make infra-local`.
# AMI Amazon Linux 2023 que o LocalStack 4.14 oferece (a EC2 é simulada).
ami_id = "ami-0532be01f26a3de55"

# Localmente a Lambda fica na raiz, com URL pública e sem CloudFront.
api_base_path               = ""
api_url_auth_type           = "NONE"
cloudfront_distribution_arn = ""

# O bootstrap (dono da política-limite) não roda no LocalStack.
usar_limite_papeis = false
