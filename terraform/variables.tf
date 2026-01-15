variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "api_port" {
  description = "Application port"
  type        = number
}

variable "instance_type" {
  description = "EC2 instance type (deprecated - using ECS Fargate)"
  type        = string
}

variable "min_size" {
  description = "Minimum number of ECS tasks"
  type        = number
}

variable "max_size" {
  description = "Maximum number of ECS tasks"
  type        = number
}

variable "desired_capacity" {
  description = "Desired number of ECS tasks"
  type        = number
}

variable "ecs_task_cpu" {
  description = "ECS Fargate task CPU"
  type        = string
}

variable "ecs_task_memory" {
  description = "ECS Fargate task memory"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL (optional - will be created by Terraform)"
  type        = string
  default     = ""
}

variable "database_engine_version" {
  description = "PostgreSQL version"
  type        = string
}

variable "database_instance_class" {
  description = "Database instance type"
  type        = string
}

variable "enable_ssl" {
  description = "Enable SSL/TLS"
  type        = bool
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}
