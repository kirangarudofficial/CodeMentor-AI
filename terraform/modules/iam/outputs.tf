output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "alb_controller_role_name" {
  description = "IAM role name for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.name
}

output "fluent_bit_role_arn" {
  description = "IAM role ARN for Fluent Bit"
  value       = aws_iam_role.fluent_bit.arn
}

output "fluent_bit_role_name" {
  description = "IAM role name for Fluent Bit"
  value       = aws_iam_role.fluent_bit.name
}
