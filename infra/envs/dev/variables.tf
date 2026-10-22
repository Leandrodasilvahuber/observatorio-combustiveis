variable "project" {
  type    = string
  default = "observatorio"
}

variable "stage" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ami_id" {
  description = "Vazio usa a Amazon Linux 2023 mais recente"
  type        = string
  default     = ""
}

variable "api_base_path" {
  description = "Prefixo do site na CloudFront"
  type        = string
  default     = "/gasolina"
}

variable "api_url_auth_type" {
  description = "AWS_IAM na AWS (só a CloudFront chama); NONE no LocalStack"
  type        = string
  default     = "AWS_IAM"
}

# Sem default: na AWS vem de TF_VAR_cloudfront_distribution_arn (variável do
# GitHub ou .env local); vazio removeria a permissão da CloudFront na Lambda.
variable "cloudfront_distribution_arn" {
  description = "CloudFront do site (www.leandrohuber.freeddns.org), dona da rota /gasolina"
  type        = string
}

# A conta tem cota de 10 execuções concorrentes e a AWS exige 10 sem reserva,
# então não dá para reservar. O cache da CloudFront segura o volume.
variable "api_reserved_concurrency" {
  type    = number
  default = -1
}

variable "api_url_id_local" {
  description = "ID fixo da Function URL no LocalStack (vazio na AWS)"
  type        = string
  default     = ""
}

variable "email_alertas" {
  description = "E-mail do alerta de orçamento (vazio não cria o alerta)"
  type        = string
  default     = ""
}
