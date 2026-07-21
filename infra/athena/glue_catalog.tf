# ──────────────────────────────────────────────────────────────────
# Glue Data Catalog — databases (namespaces lógicos), um por camada.
# As TABELAS dentro de cada database são criadas via script manual
# (sql/ddl/bronze_tables.sql e sql/ddl/silver_tables.sql),
# mesmo padrão do secrets.tf: infra via Terraform, schema via script.
# ──────────────────────────────────────────────────────────────────

resource "aws_glue_catalog_database" "bronze" {
  name = "bronze"
}

resource "aws_glue_catalog_database" "silver" {
  name = "silver"
}

resource "aws_glue_catalog_database" "gold" {
  name = "gold"
}
