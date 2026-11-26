   variable "aws_region" {
     description = "The AWS region to deploy resources in"
     type        = string
     default     = "us-east-1"
   }

   variable "domain_name" {
     description = "The registered domain name for the API"
     type        = string
     default     = "journalstarter.xyz"
   }

   variable "openai_api_key" {
     description = "The OpenAI API key for journal analysis"
     type        = string
     sensitive   = true # Prevents Terraform from printing this in the console
   }