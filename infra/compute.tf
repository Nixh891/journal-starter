# 1. Data source to get the current AWS account ID (needed for IAM policies)
data "aws_caller_identity" "current" {}

# 2. IAM Role for the EC2 Instance
resource "aws_iam_role" "ec2_role" {
  name = "journal-api-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 3. Policy to allow reading our specific SSM parameters
resource "aws_iam_role_policy" "ssm_read" {
  name = "journal-api-ssm-read"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["ssm:GetParameters"]
        Effect = "Allow"
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/journal-api/*"
        ]
      }
    ]
  })
}

# 4. Attach AWS Managed Policy for Session Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 5. Instance Profile to attach the role to the EC2 instance
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "journal-api-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# 6. Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 7. The EC2 Instance
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # A. Add 2GB swap file to prevent Out-Of-Memory (OOM) errors during Docker build
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab
              
              # B. Update and install dependencies
              dnf update -y
              dnf install -y docker git aws-cli
              
              # C. Start and enable Docker to persist across reboots
              systemctl enable --now docker
              
              # D. Fetch secrets from SSM Parameter Store
              DB_USER=$(aws ssm get-parameter --name "/journal-api/db/username" --query "Parameter.Value" --output text)
              DB_PASS=$(aws ssm get-parameter --name "/journal-api/db/password" --with-decryption --query "Parameter.Value" --output text)
              DB_NAME=$(aws ssm get-parameter --name "/journal-api/db/name" --query "Parameter.Value" --output text)
              OPENAI_KEY=$(aws ssm get-parameter --name "/journal-api/openai/api_key" --with-decryption --query "Parameter.Value" --output text)
              
              # E. Create the .env file for the application
              cat <<EOT > /app.env
              POSTGRES_USER=$DB_USER
              POSTGRES_PASSWORD=$DB_PASS
              POSTGRES_DB=$DB_NAME
              OPENAI_API_KEY=$OPENAI_KEY
              DATABASE_URL=postgresql://$DB_USER:$DB_PASS@${aws_db_instance.main.address}/$DB_NAME
              OPENAI_BASE_URL=https://api.openai.com/v1
              OPENAI_MODEL=gpt-3.5-turbo
              EOT
              
              # F. Clone the repository
              git clone https://github.com/Nixh891/journal-starter.git /app/journal-starter
              
              # G. Initialize the database schema (RDS doesn't do this automatically)
              dnf install -y postgresql15
              PGPASSWORD=$DB_PASS psql -h ${aws_db_instance.main.address} -U $DB_USER -d $DB_NAME -f /app/journal-starter/database_setup.sql
              
              # H. Build and run the Docker container
              cd /app/journal-starter
              docker build -t journal-api .
              docker run -d --name journal-api --restart always --env-file /app.env -p 8000:8000 journal-api
              EOF

  tags = {
    Name = "journal-api-app-server"
  }
}