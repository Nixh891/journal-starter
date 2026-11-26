# 1. Fetch available Availability Zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# 2. Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "journal-api-vpc"
  }
}

# 3. Internet Gateway (for public subnet / ALB)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "journal-api-igw"
  }
}

# 4. Public Subnet (for ALB)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "journal-api-public-subnet"
  }
}

# 5. Private Subnet (for EC2 App and RDS Database)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "journal-api-private-subnet"
  }
}

# Second Public Subnet (in a different AZ for ALB high availability)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1] # <-- Notice the [1]
  map_public_ip_on_launch = true

  tags = {
    Name = "journal-api-public-subnet-2"
     }
   }

# Second Private Subnet (in a different AZ for RDS high availability)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1] # <-- Notice the [1]

  tags = {
    Name = "journal-api-private-subnet-2"
     }
   }

# 6. NAT Gateway (Allows private EC2 to reach OpenAI API, blocks inbound)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "journal-api-nat"
  }
  depends_on = [aws_internet_gateway.main]
}

# 7. Route Tables
# Public route table points to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "journal-api-public-rt"
  }
}

# Private route table points to NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "journal-api-private-rt"
  }
}

# 8. Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ==========================================
# SECURITY GROUPS (The "Firewalls")
# ==========================================

# 9. ALB Security Group: Allows public HTTPS/HTTP, forwards to App
resource "aws_security_group" "alb" {
  name        = "journal-api-alb-sg"
  description = "Allow public inbound HTTP/HTTPS to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound to App"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "journal-api-alb-sg"
  }
}

# 10. App Security Group (Base definition)
resource "aws_security_group" "app" {
  name        = "journal-api-app-sg"
  description = "Allow inbound from ALB only, outbound to Internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound HTTPS to Internet (for OpenAI API)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "journal-api-app-sg"
  }
}

# 11. Database Security Group (Base definition)
resource "aws_security_group" "db" {
  name        = "journal-api-db-sg"
  description = "Allow inbound PostgreSQL from App only"
  vpc_id      = aws_vpc.main.id

  # Rules will be added below to break the cycle

  tags = {
    Name = "journal-api-db-sg"
  }
}

# 12. Security Group Rules (Breaks the cycle)
# Allow App to send traffic to DB
resource "aws_security_group_rule" "app_to_db" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.app.id
  description              = "Allow App to reach PostgreSQL"
}

# Allow DB to receive traffic from App
resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
  description              = "Allow PostgreSQL from App only"
}