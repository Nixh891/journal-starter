   # 1. Generate a secure, random password for the PostgreSQL database
   resource "random_password" "db_password" {
     length  = 16
     special = false # Prevents special characters from breaking the DATABASE_URL
     upper   = true
     lower   = true
     numeric  = true
   }
   

   # 2. Store the Database Username in SSM Parameter Store
   resource "aws_ssm_parameter" "db_user" {
     name  = "/journal-api/db/username"
     type  = "String"
     value = "postgres" # Standard default for RDS PostgreSQL
   }

   # 3. Store the Database Password securely in SSM Parameter Store
   resource "aws_ssm_parameter" "db_password" {
     name  = "/journal-api/db/password"
     type  = "SecureString"
     value = random_password.db_password.result
   }

   # 4. Store the Database Name in SSM Parameter Store
   resource "aws_ssm_parameter" "db_name" {
     name  = "/journal-api/db/name"
     type  = "String"
     value = "journaldb"
   }

   # 5. Store the OpenAI API Key securely in SSM Parameter Store
   # This reads the value from a local variable, which we will provide via a .tfvars file
    resource "aws_ssm_parameter" "openai_api_key" {
     name  = "/journal-api/openai/api_key"
     type  = "SecureString"
     value = "sk-dummy-placeholder-replace-in-aws-console" # <-- Changed to a dummy value
   }