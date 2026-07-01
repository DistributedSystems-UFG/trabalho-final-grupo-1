resource "aws_route53_zone" "internal" {
  name = var.internal_domain

  vpc {
    vpc_id = aws_vpc.main.id
  }

  comment = "Private zone para descoberta de servico entre instancias do CollabDocs"
}

locals {
  dns_records = {
    postgres     = aws_instance.data.private_ip
    rabbitmq     = aws_instance.data.private_ip
    redis        = aws_instance.data.private_ip
    java-backend = aws_instance.java_backend.private_ip
    go-collab    = aws_instance.go_collab_1.private_ip
    go-collab-2  = aws_instance.go_collab_2.private_ip
    grpc-web     = aws_instance.edge.private_ip
  }
}

resource "aws_route53_record" "internal" {
  for_each = local.dns_records

  zone_id = aws_route53_zone.internal.zone_id
  name    = each.key
  type    = "A"
  ttl     = 30
  records = [each.value]
}
