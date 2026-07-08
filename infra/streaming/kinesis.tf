# ──────────────────────────────────────────────────────────────────
# Kinesis Data Stream — recebe os trades da Binance (via producer)
# Modo on-demand: escala shards automaticamente, sem provisionar.
# ──────────────────────────────────────────────────────────────────

resource "aws_kinesis_stream" "trades" {
  name = "${var.project_name}-trades"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  retention_period = 24

  # Criptografia em repouso com a chave gerenciada da AWS
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"
}
