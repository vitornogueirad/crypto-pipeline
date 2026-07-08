# Producer da Binance — containerizado.
# Em produção rodaria em ECS/Fargate 24/7; no projeto roda sob demanda
# (local ou task Fargate pontual) para controlar custo.

FROM python:3.12-slim

WORKDIR /app

# Instala dependências primeiro (aproveita cache de layer do Docker)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Código
COPY producer.py .

# Usuário não-root
RUN useradd --create-home appuser
USER appuser

ENTRYPOINT ["python", "producer.py"]
