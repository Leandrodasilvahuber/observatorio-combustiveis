variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos"
  type        = string
}

variable "stage" {
  description = "Ambiente (dev, prd)"
  type        = string
}

variable "force_destroy" {
  description = "Permite destruir o bucket mesmo com objetos"
  type        = bool
  default     = false
}

variable "logs_retention_days" {
  type    = number
  default = 90
}
