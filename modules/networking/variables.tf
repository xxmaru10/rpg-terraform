# modules/networking/variables.tf

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
}

variable "env" {
  description = "Environment name (free, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "AZs to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH into EC2. Use your IP: [\"x.x.x.x/32\"]"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE THIS to your IP in tfvars
}

variable "create_rds_sg" {
  description = "Whether to create an RDS security group (prod only)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
