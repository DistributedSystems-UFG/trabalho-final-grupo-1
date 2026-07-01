locals {
  ecr_repos = {
    java_backend = "${var.project}-java-backend"
    go_collab    = "${var.project}-go-collab"
    frontend     = "${var.project}-frontend"
  }
}

resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repos

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = each.value }
}
