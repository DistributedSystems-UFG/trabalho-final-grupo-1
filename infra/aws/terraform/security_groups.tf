# Edge: unica instancia exposta na internet (HTTP) + SSH para diagnostico
resource "aws_security_group" "edge" {
  name        = "${var.project}-edge"
  description = "Frontend (nginx) + grpc-web (Envoy)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-edge" }
}

# go-collab: recebe trafego do edge (proxy nginx) e expoe REST+WS
resource "aws_security_group" "go" {
  name        = "${var.project}-go"
  description = "go-collab (REST proxy + WebSocket hub)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "REST/WS vindo do edge"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-go" }
}

# java-backend: REST interno (chamado pelo go-collab) + gRPC (chamado pelo envoy do edge)
resource "aws_security_group" "java" {
  name        = "${var.project}-java"
  description = "Java backend (Spring Boot REST + gRPC)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "REST interno vindo do go-collab"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.go.id]
  }

  ingress {
    description     = "gRPC vindo do envoy (edge)"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.edge.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-java" }
}

# data: postgres (so java), rabbitmq (java + go), redis (so go)
resource "aws_security_group" "data" {
  name        = "${var.project}-data"
  description = "Postgres + RabbitMQ + Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres vindo do java-backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.java.id]
  }

  ingress {
    description     = "RabbitMQ AMQP vindo do java-backend e go-collab"
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.java.id, aws_security_group.go.id]
  }

  ingress {
    description     = "Redis vindo do go-collab"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.go.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-data" }
}
