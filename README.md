# Journal Starter API - AWS Infrastructure (Phase 3 Capstone)

This repository contains the Terraform infrastructure code to deploy a secure, two-tier FastAPI Journal application to AWS. The architecture follows cloud best practices, including high availability, strict access controls, and secure secret management.

## 🏗️ Architecture Diagram

The diagram below illustrates the flow of public, private, and administrative traffic.

```mermaid
graph TD
    subgraph "Internet"
        User([User / Client])
        OpenAI([OpenAI API])
        Admin([Developer / Admin])
    end

    subgraph "AWS VPC (us-east-1)"
        subgraph "Public Subnets (2 AZs)"
            ALB["Application Load Balancer\n(Port 443 HTTPS)"]
            NAT["NAT Gateway"]
        end

        subgraph "Private Subnets (2 AZs)"
            EC2["EC2 Instance (t3.micro)\nFastAPI Docker Container\n(Port 8000)"]
            RDS[("RDS PostgreSQL\n(Private, Multi-AZ Subnet Group)")]
        end
    end

    subgraph "AWS Management"
        SSM["Systems Manager\nParameter Store"]
        IAM["IAM Role (Least Privilege)"]
    end

    %% Traffic Flows
    User -->|1. Public HTTPS Traffic| ALB
    ALB -->|2. Private HTTP Traffic| EC2
    EC2 -->|3. Database Queries (Port 5432)| RDS
    EC2 -->|4. Outbound AI Requests| NAT
    NAT -->|5. Internet Access| OpenAI
    
    Admin -->|6. Secure Shell-less Access| SSM
    SSM -.->|7. Fetch Secrets| EC2
    EC2 -.->|8. Assume Role| IAM
```

---

## ⚙️ Services Selected & Expected Cost

| Service | Purpose | Estimated Monthly Cost (us-east-1) |
| :--- | :--- | :--- |
| **VPC & Subnets** | Network isolation (2 Public, 2 Private) | Free |
| **Application Load Balancer** | HTTPS termination and traffic distribution | ~$18.00 |
| **NAT Gateway** | Outbound internet access for private EC2 | ~$32.00 |
| **EC2 (t3.micro)** | Compute tier running Dockerized FastAPI app | ~$8.00 |
| **RDS PostgreSQL (db.t3.micro)** | Managed, highly available database | ~$15.00 |
| **Route 53** | DNS routing for `journalstarter.xyz` | ~$0.50 |
| **ACM** | Free SSL/TLS certificate management | Free |
| **SSM Parameter Store** | Secure storage for DB credentials and API keys | Free (Standard tier) |
| **Total Estimated Cost** | | **~$73.50 / month** |

*(Note: Costs are estimates based on 730 hours/month. Tearing down resources via `terraform destroy` reduces compute/networking costs to $0, leaving only the ~$0.50/month Route 53 domain registration).*

---

## 🔒 Access Controls

1. **Network Security (Security Groups)**:
   - **ALB SG**: Allows inbound HTTPS (443) from `0.0.0.0/0`.
   - **EC2 SG**: Allows inbound HTTP (8000) **only** from the ALB Security Group. No public inbound access.
   - **RDS SG**: Allows inbound PostgreSQL (5432) **only** from the EC2 Security Group.
2. **IAM Least Privilege**: The EC2 instance is assigned a dedicated IAM Role (`journal-api-ec2-role`) that grants **only** `ssm:GetParameters` for the `/journal-api/*` path and `AmazonSSMManagedInstanceCore` for Session Manager access. It cannot modify AWS resources.
3. **No SSH Access**: Port 22 is completely closed. Administrative access is handled securely via AWS Systems Manager (SSM) Session Manager.

---

## 🤖 AI Model and Safety Controls

- **Model**: `gpt-3.5-turbo` (configured via environment variables).
- **Secret Management**: The `OPENAI_API_KEY` is **never** hardcoded in the repository. It is stored as a `SecureString` in AWS SSM Parameter Store and fetched dynamically by the EC2 `user_data` script at boot time.
- **Input Validation**: All API inputs are strictly validated by FastAPI and Pydantic before being processed or sent to the LLM, preventing prompt injection or malformed payloads.

---

## ✅ Deployment Constraints Passed (Evidence)

| Constraint | Evidence in Code / Architecture |
| :--- | :--- |
| **High Availability (2 AZs)** | `network.tf` creates public and private subnets in two distinct Availability Zones. Both the ALB and RDS Subnet Group reference both subnets. |
| **Private Compute Tier** | `compute.tf` places the EC2 instance in `aws_subnet.private.id`. It has no public IP and no Internet Gateway route. |
| **HTTPS Enforcement** | `alb.tf` provisions an ACM certificate and configures the ALB listener to accept only HTTPS (443) traffic. |
| **Secure Secret Handling** | `secrets.tf` uses `random_password` and `aws_ssm_parameter` (SecureString). The `user_data` script fetches these at runtime. |
| **No Hardcoded Secrets** | `.gitignore` explicitly excludes `.env`, `terraform.tfvars`, and `*.tfstate` files. |

---

## ⚠️ Limitation to Address Before Production

**Single Point of Failure in Compute Tier**: Currently, the application runs on a single `t3.micro` EC2 instance. If this instance fails or experiences high load, the application will become unavailable or degrade. 
* **Production Fix**: Replace the single `aws_instance` resource with an **Auto Scaling Group (ASG)** and a Launch Template. This would ensure automatic healing of unhealthy instances and horizontal scaling based on CPU/Memory metrics from the ALB Target Group.

*(Note: The `/entries/{id}/analyze` endpoint requires a valid, billing-enabled OpenAI API key. For security and cost reasons, a placeholder key is used in this repository. To test, update the `/journal-api/openai/api_key` parameter in AWS SSM with a valid `sk-...` key and restart the container).*

---

## 🧹 Phase 5 Prep: Resource Cleanup & Billing Check

To avoid unexpected charges, destroy the infrastructure when it is no longer needed.

### 1. Destroy Terraform Resources
Run the following command in your terminal from the `infra/` directory:
```bash
terraform destroy -auto-approve
```
*Note: This will terminate the EC2, RDS, ALB, NAT Gateway, and associated networking components. It will **not** delete your Route 53 hosted zone or domain registration, which you may want to keep.*

### 2. Verify Billing
1. Log in to the AWS Management Console.
2. Search for and open the **Billing and Cost Management** dashboard.
3. Click on **Bills** in the left navigation pane.
4. Expand the services (e.g., EC2, RDS, NAT Gateway) to verify that usage has dropped to zero or is only reflecting the time the resources were actively running.
5. (Optional) Set up a **Billing Alert** in AWS Budgets to notify you if monthly charges exceed $5.00.


## ⚠️ Note on OpenAI Integration
The `/entries/{id}/analyze` endpoint requires a valid, billing-enabled OpenAI API key. 
For security and cost reasons, a dummy key is provisioned in this repository's Terraform state. 
To test the analysis feature, update the `/journal-api/openai/api_key` parameter in AWS Systems Manager Parameter Store with your own valid `sk-...` key, and restart the EC2 Docker container.

