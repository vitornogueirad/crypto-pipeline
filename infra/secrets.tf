# ──────────────────────────────────────────────────────────────────
# Secrets Manager — guarda a API key da CoinGecko
# ──────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "coingecko" {
  name        = "${var.project_name}/coingecko-api-key"
  description = "API key da CoinGecko"
}
