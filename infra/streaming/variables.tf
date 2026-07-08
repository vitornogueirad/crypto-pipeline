variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile SSO"
  type        = string
  default     = "portfolio-dev"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "crypto-pipeline"
}

variable "data_lake_bucket" {
  description = "Nome do bucket do data lake"
  type        = string
}

variable "dedup_ttl_hours" {
  description = "Horas que um trade_id fica na tabela de dedup antes do TTL expirar"
  type        = number
  default     = 6
}

variable "iterator_age_alarm_ms" {
  description = "Limite de IteratorAge (ms) para disparar alarme de consumer atrasado"
  type        = number
  default     = 60000 # 60s
}

variable "alert_email" {
  description = "E-mail para alarmes do streaming"
  type        = string
}
