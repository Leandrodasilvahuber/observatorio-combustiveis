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

# O GitHub emite o "sub" do token com os IDs do dono e do repositório
# (subject imutável): renomear ou recriar um repositório com o mesmo nome não
# herda o acesso. Valor em:
#   gh api repos/<dono>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
variable "github_sub_prefixo" {
  description = "Prefixo do sub do token OIDC do repositório que pode fazer deploy"
  type        = string
  default     = "repo:Leandrodasilvahuber@45015902/observatorio-combustiveis@1429861598"
}
