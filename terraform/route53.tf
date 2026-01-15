# Route53 configuration for API subdomain

# Data source to get the hosted zone for the main domain
data "aws_route53_zone" "main" {
  name = var.domain_name
  private_zone = false
}

# DNS record for API subdomain pointing to the load balancer
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# DNS record for root domain pointing to the load balancer
resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Output the DNS name for reference
output "api_domain" {
  description = "API domain name"
  value       = aws_route53_record.api.fqdn
}

output "root_domain" {
  description = "Root domain name"
  value       = aws_route53_record.root.fqdn
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.main.dns_name
}
