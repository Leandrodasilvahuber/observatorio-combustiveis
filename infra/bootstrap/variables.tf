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

variable "github_repo" {
  description = "Repositório (dono/nome) que pode assumir o papel de deploy"
  type        = string
  default     = "Leandrodasilvahuber/observatorio-combustiveis"
}
