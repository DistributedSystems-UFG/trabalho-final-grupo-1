variable "aws_region" {
  description = "Regiao AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo usado para nomear os recursos"
  type        = string
  default     = "collabdocs"
}

variable "allowed_ssh_cidr" {
  description = "CIDR autorizado a acessar a porta 22 (ex: \"SEU_IP/32\"). Sem default por seguranca."
  type        = string
}

variable "instance_type_small" {
  description = "Tipo de instancia para data e java-backend (mais RAM)"
  type        = string
  default     = "t3.small"
}

variable "instance_type_micro" {
  description = "Tipo de instancia para go-collab e edge"
  type        = string
  default     = "t3.micro"
}

variable "az_a" {
  description = "Primeira AZ usada (data, java-backend, go-collab-1, edge)"
  type        = string
  default     = "us-east-1a"
}

variable "az_b" {
  description = "Segunda AZ usada (go-collab-2, para distribuir failover entre AZs)"
  type        = string
  default     = "us-east-1b"
}

variable "internal_domain" {
  description = "Dominio da private hosted zone do Route53 para descoberta de servico"
  type        = string
  default     = "collabdocs.internal"
}

variable "db_name" {
  type    = string
  default = "collabdocs"
}

variable "db_user" {
  type    = string
  default = "collabdocs"
}

variable "rabbitmq_user" {
  type    = string
  default = "collabdocs"
}
