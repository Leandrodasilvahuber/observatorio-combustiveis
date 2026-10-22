import os

# O handler cria o cliente S3 na importação; nenhum teste fala com a AWS.
# O Makefile exporta o .env, então o AWS_PROFILE real é descartado aqui.
os.environ.pop("AWS_PROFILE", None)
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
