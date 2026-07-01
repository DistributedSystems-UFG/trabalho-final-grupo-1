resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "rabbitmq" {
  length  = 24
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 40
  special = false
}
