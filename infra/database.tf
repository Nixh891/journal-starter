# 1. Subnet Group for RDS (Must be in private subnets)
resource "aws_db_subnet_group" "main" {
    name       = "journal-api-db-subnet-group"
    subnet_ids = [aws_subnet.private.id, aws_subnet.private_2.id] # <-- Updated

    tags = {
        Name = "journal-api-db-subnet-group"
     }
   }

# 2. The PostgreSQL RDS Instance
resource "aws_db_instance" "main" {
  identifier           = "journal-api-db"
  engine               = "postgres"
  instance_class       = "db.t3.micro" # Free-tier eligible, low cost
  
  # Storage
  allocated_storage    = 20 # GB
  storage_type         = "gp3"
  
  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  
  # Credentials (pulled from the random password we generated)
  username             = "postgres"
  password             = random_password.db_password.result
  
  # Database name
  db_name              = "journaldb"
  
  # Important for this exercise: 
  # We skip the final snapshot to avoid ongoing S3 storage charges after we run `terraform destroy`.
  # WARNING: In a real production environment, you would set this to `true` to prevent data loss.
  skip_final_snapshot  = true
  
  # Performance & Maintenance
  multi_az               = false # Single AZ is sufficient for this exercise and keeps costs low
  publicly_accessible    = false # STRICTLY PRIVATE
  
  tags = {
    Name = "journal-api-db"
  }
}