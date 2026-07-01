output "edge_public_ip" {
  description = "IP publico do frontend (CollabDocs)"
  value       = aws_instance.edge.public_ip
}

output "edge_url" {
  description = "URL para acessar a aplicacao"
  value       = "http://${aws_instance.edge.public_ip}"
}

output "instance_ips" {
  description = "IP publico de cada instancia (para SSH/diagnostico)"
  value = {
    data         = aws_instance.data.public_ip
    java_backend = aws_instance.java_backend.public_ip
    go_collab_1  = aws_instance.go_collab_1.public_ip
    go_collab_2  = aws_instance.go_collab_2.public_ip
    edge         = aws_instance.edge.public_ip
  }
}

output "ssh_key_path" {
  description = "Caminho local da chave privada para SSH"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_commands" {
  description = "Comandos prontos para SSH em cada instancia"
  value = {
    data         = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.data.public_ip}"
    java_backend = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.java_backend.public_ip}"
    go_collab_1  = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.go_collab_1.public_ip}"
    go_collab_2  = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.go_collab_2.public_ip}"
    edge         = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.edge.public_ip}"
  }
}

output "ecr_repository_urls" {
  description = "URIs dos repositorios ECR usados pelo push-images.sh"
  value = {
    java_backend = aws_ecr_repository.this["java_backend"].repository_url
    go_collab    = aws_ecr_repository.this["go_collab"].repository_url
    frontend     = aws_ecr_repository.this["frontend"].repository_url
  }
}

output "aws_region" {
  value = var.aws_region
}
