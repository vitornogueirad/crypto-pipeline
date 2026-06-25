variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile SSO configurado via 'aws configure sso'"
  type        = string
  default     = "dev"
}

variable "environment" {
  description = "Ambiente (dev, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "crypto-pipeline"
}

variable "coins" {
  description = "Moedas a coletar (ids da CoinGecko, separados por vírgula)"
  type        = string
  default     = "bitcoin,ethereum,solana,cardano"
}

variable "ingestion_schedule" {
  description = "Expressão de agendamento do EventBridge"
  type        = string
  default     = "rate(1 hour)"
}

variable "billing_alert_threshold" {
  description = "Valor em USD para disparar o alarme de billing"
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "E-mail para receber alertas de billing"
  type        = string
}
