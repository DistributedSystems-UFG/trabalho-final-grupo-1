data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ami_id     = data.aws_ssm_parameter.al2023_ami.value

  java_image     = "${aws_ecr_repository.this["java_backend"].repository_url}:latest"
  go_image       = "${aws_ecr_repository.this["go_collab"].repository_url}:latest"
  frontend_image = "${aws_ecr_repository.this["frontend"].repository_url}:latest"
}

resource "aws_instance" "data" {
  ami                    = local.ami_id
  instance_type          = var.instance_type_small
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.data.id]
  key_name               = aws_key_pair.ssh.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/templates/data.sh.tpl", {
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = random_password.db.result
    rabbitmq_user     = var.rabbitmq_user
    rabbitmq_password = random_password.rabbitmq.result
    init_sql          = file("${path.module}/../../postgres/init.sql")
    seed_sql          = file("${path.module}/../../postgres/seed.sql")
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-data" }
}

resource "aws_instance" "java_backend" {
  ami                    = local.ami_id
  instance_type          = var.instance_type_small
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.java.id]
  key_name               = aws_key_pair.ssh.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  user_data = templatefile("${path.module}/templates/java-backend.sh.tpl", {
    region            = var.aws_region
    account_id        = local.account_id
    image             = local.java_image
    internal_domain   = var.internal_domain
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = random_password.db.result
    rabbitmq_user     = var.rabbitmq_user
    rabbitmq_password = random_password.rabbitmq.result
    jwt_secret        = random_password.jwt_secret.result
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-java-backend" }
}

resource "aws_instance" "go_collab_1" {
  ami                    = local.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.go.id]
  key_name               = aws_key_pair.ssh.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  user_data = templatefile("${path.module}/templates/go-collab.sh.tpl", {
    region            = var.aws_region
    account_id        = local.account_id
    image             = local.go_image
    internal_domain   = var.internal_domain
    rabbitmq_user     = var.rabbitmq_user
    rabbitmq_password = random_password.rabbitmq.result
    jwt_secret        = random_password.jwt_secret.result
    container_name    = "collabdocs-go-collab"
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-go-collab-1" }
}

resource "aws_instance" "go_collab_2" {
  ami                    = local.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = aws_subnet.public_b.id
  vpc_security_group_ids = [aws_security_group.go.id]
  key_name               = aws_key_pair.ssh.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  user_data = templatefile("${path.module}/templates/go-collab.sh.tpl", {
    region            = var.aws_region
    account_id        = local.account_id
    image             = local.go_image
    internal_domain   = var.internal_domain
    rabbitmq_user     = var.rabbitmq_user
    rabbitmq_password = random_password.rabbitmq.result
    jwt_secret        = random_password.jwt_secret.result
    container_name    = "collabdocs-go-collab-2"
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-go-collab-2" }
}

resource "aws_instance" "edge" {
  ami                    = local.ami_id
  instance_type          = var.instance_type_micro
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.edge.id]
  key_name               = aws_key_pair.ssh.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  user_data = templatefile("${path.module}/templates/edge.sh.tpl", {
    region         = var.aws_region
    account_id     = local.account_id
    frontend_image = local.frontend_image
    nginx_conf     = file("${path.module}/../config/nginx.aws.conf")
    envoy_yaml     = file("${path.module}/../config/envoy.aws.yaml")
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-edge" }
}
