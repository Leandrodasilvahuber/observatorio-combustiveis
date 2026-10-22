variable "project" {
  type = string
}

variable "stage" {
  type = string
}

variable "source_dir" {
  description = "Pasta da API (handler.py e mapa_brasil.json)"
  type        = string
}

variable "bucket_name" {
  type = string
}

variable "bucket_arn" {
  type = string
}

variable "prefixo_resultados" {
  type    = string
  default = "resultados"
}

# Limita o custo de abuso da URL pública. Contas novas da AWS costumam ter
# cota total de 10 execuções concorrentes e não permitem reservar; nesse caso
# use -1 (sem reserva) até pedir aumento da cota.
variable "reserved_concurrency" {
  type    = number
  default = 5
}

variable "base_path" {
  description = "Prefixo do site atrás da CloudFront (ex.: /gasolina); vazio na raiz"
  type        = string
  default     = ""
}

variable "url_auth_type" {
  description = "AWS_IAM (só a CloudFront chama, via OAC) ou NONE (URL pública)"
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.url_auth_type)
    error_message = "url_auth_type deve ser AWS_IAM ou NONE."
  }
}

variable "cloudfront_distribution_arn" {
  description = "Distribuição que pode chamar a Function URL (vazio: nenhuma)"
  type        = string
  default     = ""
}

# Só no LocalStack: fixa o ID da Function URL (tag _custom_id_), para a URL
# local não mudar a cada recriação. Na AWS fica vazio.
variable "url_id_local" {
  type    = string
  default = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "permissions_boundary" {
  description = "ARN da política-limite dos papéis (null no LocalStack)"
  type        = string
  default     = null
}
