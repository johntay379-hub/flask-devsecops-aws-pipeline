variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "secure-flask"
}

variable "github_repo" {
  description = "GitHub repo in format owner/repo-name"
  type        = string
  default     = "johntay379-hub/secure-flask-app"
}
