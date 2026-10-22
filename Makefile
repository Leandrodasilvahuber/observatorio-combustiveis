SHELL := /bin/bash
-include .env
export

ENV        ?= dev
REGION     ?= $(or $(AWS_REGION),us-east-1)
# ID fixo da Function URL local; o serviço home do compose usa o mesmo valor
API_URL_ID_LOCAL ?= observatorio
TF_DIR     := infra/envs/$(ENV)
OVERRIDE   := $(TF_DIR)/localstack_providers_override.tf
TFVARS_LS  := $(TF_DIR)/localstack.auto.tfvars
PACOTE     := $(TF_DIR)/build/observatorio.tar.gz
TF_STATE   := $(TF_DIR)/terraform.localstack.tfstate
TF         := terraform -chdir=$(TF_DIR)
# Alvos locais ignoram o AWS_PROFILE do .env para nunca tocar a conta real
TFL        := env -u AWS_PROFILE TF_VAR_region=$(REGION) TF_VAR_api_url_id_local=$(API_URL_ID_LOCAL) $(TF)
AWSLS      := env -u AWS_PROFILE AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url=http://localhost:4566 --region $(REGION)
COMPOSE    := docker compose
AIRFLOW    := $(COMPOSE) exec airflow airflow
PSQL       := $(COMPOSE) exec postgres psql -U observatorio -d observatorio
DAG_ID     := observatorio_combustiveis

.DEFAULT_GOAL := help

help: ## Lista os comandos
	@grep -hE '^[a-zA-Z_-]+:.*?## ' Makefile | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

.env:
	cp .env.example .env
	@echo "Criado .env a partir do .env.example; revise as senhas."

# --- Ambiente local --------------------------------------------------------

up: .env ## Sobe LocalStack, Postgres e Airflow e cria o bucket
	$(COMPOSE) up -d --build --wait
	$(MAKE) infra-local
	@echo "Airflow: http://localhost:8080"

down: ## Para tudo (mantém os dados do Postgres)
	$(COMPOSE) down

reset: ## Para tudo e apaga os volumes (Postgres e logs)
	$(COMPOSE) down -v
	rm -f $(TF_STATE) $(TF_STATE).backup

logs: ## Logs de todos os serviços
	$(COMPOSE) logs -f

ps: ## Status dos contêineres
	$(COMPOSE) ps

# O LocalStack não persiste dados: se o bucket sumiu, o state local está
# obsoleto e é descartado antes de recriar.
infra-local: pacote ## Aplica o Terraform no LocalStack
	cp infra/localstack/localstack_override.tf $(OVERRIDE)
	cp infra/localstack/localstack.auto.tfvars $(TFVARS_LS)
	@$(AWSLS) s3api head-bucket --bucket $(OBS_BUCKET) >/dev/null 2>&1 || rm -f $(TF_STATE) $(TF_STATE).backup
	$(TFL) init -reconfigure -input=false >/dev/null
	$(TFL) apply -auto-approve -input=false

# --- Pipeline --------------------------------------------------------------

dag-test: ## Executa a DAG uma vez, em primeiro plano, mostrando o log
	$(AIRFLOW) dags test $(DAG_ID)

dag-run: ## Despausa a DAG (agenda de 10 dias) e dispara uma execução
	$(AIRFLOW) dags unpause $(DAG_ID)
	$(AIRFLOW) dags trigger $(DAG_ID)

bronze-ls: ## Lista os arquivos no S3 bronze
	$(AWSLS) s3 ls s3://$(OBS_BUCKET)/bronze/ --recursive --human-readable

raw-stats: ## Linhas por arquivo em raw.precos_anp
	$(PSQL) -c "select arquivo_origem, count(*) linhas, max(carregado_em) carregado_em from raw.precos_anp group by 1 order by 1"

dbt-build: ## Roda modelos e testes do dbt
	$(COMPOSE) exec airflow /opt/dbt/bin/dbt build --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt

marts-stats: ## Resumo das tabelas do dbt
	$(PSQL) -c "select 'raw.precos_anp' tabela, count(*) linhas from raw.precos_anp union all select 'staging.stg_precos', count(*) from staging.stg_precos union all select 'marts.fct_precos', count(*) from marts.fct_precos union all select 'marts.agg_uf_periodo', count(*) from marts.agg_uf_periodo union all select 'marts.agg_etanol_compensa', count(*) from marts.agg_etanol_compensa"

api-url: ## URL da API (Function URL)
	@$(TFL) output -raw api_url; echo

api-test: ## Chama a API local: home (mapa), JSON e período inválido
	@URL=$$($(TFL) output -raw api_url); \
	echo "== GET /"; curl -s -o /dev/null -w "%{http_code} %{content_type}\n" "$$URL"; \
	echo "== GET /?formato=json"; curl -s "$$URL?formato=json" | head -c 300; echo; \
	echo "== GET /?periodo=17-10-2026"; curl -s "$$URL?periodo=17-10-2026"; echo

resultados-ls: ## Lista os JSON publicados
	$(AWSLS) s3 ls s3://$(OBS_BUCKET)/resultados/ --human-readable

psql: ## Abre o psql no banco do projeto
	$(PSQL)

test: .venv ## Testes unitários do pipeline
	.venv/bin/pytest -q

SHELL_SCRIPTS := ec2/*.sh postgres/init/*.sh infra/modules/runner/user_data.sh.tftpl
TF_RAIZES     := infra/bootstrap infra/envs/$(ENV)

lint: .venv ## Análise estática: ruff, shellcheck, terraform fmt/validate e tflint
	.venv/bin/ruff check .
	.venv/bin/ruff format --check .
	.venv/bin/shellcheck $(SHELL_SCRIPTS)
	terraform fmt -recursive -check infra
	@rm -f $(OVERRIDE)
	@for d in $(TF_RAIZES); do \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	  tflint --chdir=$$d --config=$(CURDIR)/.tflint.hcl || exit 1; \
	done

.venv: requirements-dev.txt
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements-dev.txt
	touch .venv

# --- AWS -------------------------------------------------------------------

# Pacote que a EC2 baixa a cada boot. Determinístico (ordem, datas, dono e
# permissões fixos) para o Terraform só reenviar quando o conteúdo mudar. Só
# entram arquivos versionados: logs e caches locais (dbt/logs, __pycache__)
# ficam de fora, e o pacote local sai igual ao do CI.
pacote: ## Gera o pacote do projeto enviado para a EC2
	@mkdir -p $(dir $(PACOTE))
	@git ls-files -z docker-compose.aws.yml airflow dags dbt ec2 postgres | \
	  tar --null -T - --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=go-w \
	  -cf - | gzip -n > $(PACOTE)
	@echo "$(PACOTE) ($$(du -h $(PACOTE) | cut -f1))"

# Bucket do state: leva o ID da conta, que não fica no repositório
TF_STATE_BUCKET = observatorio-tfstate-$$(aws sts get-caller-identity --query Account --output text)

aws-init: pacote
	@[ -n "$$TF_VAR_cloudfront_distribution_arn" ] || { echo "defina TF_VAR_cloudfront_distribution_arn no .env"; exit 1; }
	rm -f $(OVERRIDE) $(TFVARS_LS)
	$(TF) init -reconfigure -input=false -backend-config="bucket=$(TF_STATE_BUCKET)" >/dev/null

plan-aws: aws-init ## Plano contra a AWS real (usa AWS_PROFILE)
	$(TF) plan -input=false

deploy-aws: aws-init ## Deploy na AWS real (pede confirmação)
	$(TF) apply -input=false

destroy-aws: aws-init ## Destroi a infra na AWS real, inclusive o bronze (pede confirmação)
	$(TF) destroy -input=false

# Os alvos aws-* dependem de aws-init para nunca lerem o state do LocalStack.
INSTANCE    = $$($(TF) output -raw instance_id)
BUCKET_AWS  = $$($(TF) output -raw bucket_name)

aws-ligar: aws-init ## Liga a EC2 agora (roda um ciclo e desliga sozinha)
	aws ec2 start-instances --instance-ids $(INSTANCE) --output table

aws-manutencao: aws-init ## Ativa o modo manutenção (a EC2 não roda nem desliga)
	aws s3api put-object --bucket $(BUCKET_AWS) --key config/MANUTENCAO >/dev/null && echo "manutenção ativada"

aws-fim-manutencao: aws-init ## Desativa o modo manutenção
	aws s3api delete-object --bucket $(BUCKET_AWS) --key config/MANUTENCAO && echo "manutenção desativada"

aws-tunel: aws-init ## Airflow da EC2 em localhost:8080 (Session Manager)
	aws ssm start-session --target $(INSTANCE) --document-name AWS-StartPortForwardingSession \
	  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'

aws-shell: aws-init ## Terminal na EC2 (Session Manager)
	aws ssm start-session --target $(INSTANCE)

aws-ultimo-log: aws-init ## Mostra o log do último ciclo
	@KEY=$$(aws s3api list-objects-v2 --bucket $(BUCKET_AWS) --prefix logs/ciclo- --query 'sort_by(Contents,&LastModified)[-1].Key' --output text); \
	echo "== s3://$(BUCKET_AWS)/$$KEY"; aws s3 cp "s3://$(BUCKET_AWS)/$$KEY" -

fmt: ## Formata o Terraform
	terraform fmt -recursive infra

.PHONY: help up down reset logs ps infra-local dag-test dag-run bronze-ls raw-stats dbt-build marts-stats api-url api-test resultados-ls psql test lint pacote aws-init plan-aws deploy-aws destroy-aws aws-ligar aws-manutencao aws-fim-manutencao aws-tunel aws-shell aws-ultimo-log fmt
