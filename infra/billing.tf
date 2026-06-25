# ──────────────────────────────────────────────────────────────────
# AWS Budgets — controle de custo via IaC.
# Teto MENSAL recorrente com alertas escalonados por e-mail.
# ──────────────────────────────────────────────────────────────────

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-limit"
  budget_type  = "COST"
  limit_amount = tostring(var.billing_alert_threshold)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alerta 1 — gasto REAL atingiu 50% do teto (aviso preventivo)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Alerta 2 — gasto REAL atingiu 80% do teto (atenção)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Alerta 3 — PREVISÃO de estourar 100% do teto no fim do mês
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
