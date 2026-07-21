variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos"
  type        = string
  default     = "crypto-pipeline"
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "data_lake_bucket" {
  description = "Nome do bucket do data lake (mesmo da Etapa 1 — contém bronze/, silver/ e gold/)"
  type        = string
}

variable "athena_bytes_scanned_cutoff" {
  description = "Trava de custo: bytes escaneados por query no Athena antes de abortar (padrão: 1 GB)"
  type        = number
  default     = 1073741824
}

variable "query_results_retention_days" {
  description = "Dias até o resultado de query no bucket de staging expirar (dado efêmero, não é o data lake)"
  type        = number
  default     = 3
}

variable "alert_email" {
  description = "E-mail para alarmes das Lambdas de transformação (silver)"
  type        = string
}

variable "transform_schedule_expression" {
  description = "Frequência de disparo das Lambdas de transformação bronze -> silver"
  type        = string
  default     = "rate(15 minutes)"
}

variable "gold_schedule_expression" {
  description = "Frequência de disparo da Lambda de gold. Separada da silver porque a query de gold escaneia a tabela inteira (window function no baseline móvel) — pode precisar rodar mais espaçada conforme o histórico crescer, sem depender do schedule da silver."
  type        = string
  default     = "rate(15 minutes)"
}

variable "lambda_timeout_seconds" {
  description = "Timeout de cada Lambda (2 partições x até 2min de polling cada no Athena, com folga)"
  type        = number
  default     = 300
}

variable "log_retention_days" {
  description = "Retenção dos logs no CloudWatch (evita acúmulo indefinido e custo crescente)"
  type        = number
  default     = 14
}
