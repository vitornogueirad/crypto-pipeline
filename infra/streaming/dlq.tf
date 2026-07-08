# ──────────────────────────────────────────────────────────────────
# SQS Dead-Letter Queue — destino on-failure do Event Source Mapping
# Recebe metadados dos batches que falharam após esgotar os retries.
# ──────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "consumer_dlq" {
  name = "${var.project_name}-trades-consumer-dlq"

  # Retém mensagens falhas por 14 dias (máximo) para investigação
  message_retention_seconds = 1209600

  # Criptografia em repouso
  sqs_managed_sse_enabled = true
}
