variable "vpc_cidr" {
  description = "CIDR IPv4 đã được quy hoạch cho VPC dev."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR của hai public subnet trong VPC dev."
  type        = list(string)
}

variable "map_public_ip_on_launch" {
  description = "Có tự động gán public IPv4 cho tài nguyên mới trong public subnet hay không."
  type        = bool
  default     = false
}