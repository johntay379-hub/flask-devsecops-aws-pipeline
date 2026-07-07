output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.app.repository_url
}

output "ec2_public_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.app.public_ip
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "instance_id" {
  description = "EC2 instance ID for SSM access"
  value       = aws_instance.app.id
}

output "alb_dns_name" {
  description = "ALB DNS name — visit this in your browser"
  value       = aws_lb.app.dns_name
}
