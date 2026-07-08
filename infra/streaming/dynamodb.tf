# ──────────────────────────────────────────────────────────────────
# DynamoDB — tabela de deduplicação (idempotência)
# Guarda os trade_id já processados. TTL limpa os antigos sozinho.
# ──────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "dedup" {
  name         = "${var.project_name}-trades-dedup"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "trade_id"

  attribute {
    name = "trade_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }
}
