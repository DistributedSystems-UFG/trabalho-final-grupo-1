# AWS Academy Learner Lab nao permite iam:CreateRole / iam:PutRolePolicy
# para o usuario do lab. O ambiente ja fornece "LabRole" (com
# AmazonEC2ContainerRegistryReadOnly anexada, entre outras) e o instance
# profile "LabInstanceProfile" que a referencia — reusamos os dois em vez
# de criar uma role nova.
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}
