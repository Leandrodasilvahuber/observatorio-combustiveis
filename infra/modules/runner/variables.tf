variable "project" {
  type = string
}

variable "stage" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "bucket_arn" {
  type = string
}

variable "pacote_path" {
  description = "Pacote .tar.gz do projeto (gerado por `make pacote`)"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "volume_size_gb" {
  type    = number
  default = 30
}

variable "ami_id" {
  description = "Vazio usa a Amazon Linux 2023 mais recente (parâmetro SSM público)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Vazio usa uma subnet da VPC padrão"
  type        = string
  default     = ""
}

variable "schedule_expression" {
  type    = string
  default = "rate(10 days)"
}

variable "compose_version" {
  type    = string
  default = "v5.5.1"
}

variable "buildx_version" {
  type    = string
  default = "v0.37.2"
}
