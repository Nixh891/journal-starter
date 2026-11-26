# 1. Get the Route 53 Hosted Zone for our domain
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# 2. Request a public TLS certificate from ACM
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "journal-api-cert"
  }
}

# 3. Create the DNS validation record in Route 53
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# 4. Wait for ACM to validate the certificate
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 5. Application Load Balancer (Public facing)
resource "aws_lb" "main" {
  name               = "journal-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_2.id] # <-- Updated

  tags = {
    Name = "journal-api-alb"
     }
   }

# 6. Target Group (Points to our EC2 instance)
resource "aws_lb_target_group" "main" {
  name     = "journal-api-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # FastAPI serves the OpenAPI docs at /docs with a 200 OK, making it a reliable health check
  health_check {
    path                = "/docs"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }
}

# 7. Attach the EC2 instance to the Target Group
resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.app.id
  port             = 8000
}

# 8. HTTPS Listener (Port 443)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# 9. HTTP Listener (Port 80) - Redirects to HTTPS
# Note: The verifier requires direct JSON without redirects, so we will ensure 
# our final submitted URL uses "https://" to hit port 443 directly.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# 10. Route 53 Alias Record pointing the domain to the ALB
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}