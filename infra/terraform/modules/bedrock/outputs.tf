# Bedrock Module Outputs

output "kong_role_arn" {
  description = "ARN of the IAM role for Kong service account"
  value       = aws_iam_role.kong_bedrock.arn
}

output "kong_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.kong_bedrock.name
}

output "helm_service_account_annotations" {
  description = "Helm values for service account annotations"
  value = {
    "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = aws_iam_role.kong_bedrock.arn
  }
}

output "kubectl_annotate_command" {
  description = "kubectl command to annotate service account"
  value       = "kubectl annotate serviceaccount -n ${var.namespace} ${var.service_account} eks.amazonaws.com/role-arn=${aws_iam_role.kong_bedrock.arn}"
}
