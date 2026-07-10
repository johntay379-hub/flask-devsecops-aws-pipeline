# 🔐 Flask DevSecOps AWS Pipeline

![Python](https://img.shields.io/badge/Python-Flask-3776AB?style=for-the-badge&logo=python)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?style=for-the-badge&logo=docker)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?style=for-the-badge&logo=githubactions)
![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?style=for-the-badge&logo=amazonaws)
![Trivy](https://img.shields.io/badge/Trivy-Security_Scan-red?style=for-the-badge)
![Status](https://img.shields.io/badge/Pipeline-Passing-brightgreen?style=for-the-badge)

---

## What is this?

A production-style containerized Flask application deployed on AWS using a fully automated DevSecOps pipeline. Every time code is pushed to GitHub, the pipeline builds a Docker image, scans it for vulnerabilities with Trivy, pushes it to a private ECR registry, and deploys it to EC2 — all without a single hardcoded AWS credential or SSH key.

Security is not an afterthought here. It is built into every layer: credential-less AWS authentication via OIDC, container vulnerability scanning before deployment, least-privilege IAM roles, SSM-based remote access without SSH, and traffic flowing exclusively through a load balancer.

---

## Live Demo

The infrastructure was deployed, tested, and screenshotted, then torn down with terraform destroy to avoid ongoing AWS charges. Screenshots in /screenshots show the live deployment. The full stack can be redeployed in minutes.

ALB endpoint when live:
```
http://secure-flask-alb-1046257647.us-east-1.elb.amazonaws.com
```

API responses:
```json
GET /
{"hostname": "f5ed7d14b8a7", "message": "Secure Containerised Flask App", "status": "running"}

GET /health
{"status": "healthy"}
```

The hostname field returns the Docker container ID — proof the app is running inside a container, not directly on the host.

---

## The Flask Application

A lightweight Python Flask API with two endpoints:

```python
GET /        returns app info including container hostname
GET /health  returns health check status used by ALB
```

The app runs on Gunicorn — a production WSGI server, not Flask built-in development server. Flask dev server is single-threaded and not designed for production traffic. Gunicorn handles multiple concurrent requests properly.

```dockerfile
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
```

---

## How the pipeline works

### Every push to main triggers the full pipeline

**Step 1 — OIDC Authentication**

GitHub Actions never sees AWS access keys. Instead, GitHub generates a signed JWT token proving "I am GitHub Actions running for repo johntay379-hub/flask-devsecops-aws-pipeline." AWS verifies this token against the OIDC provider and issues a temporary session credential. No long-lived credentials anywhere.

**Step 2 — Docker Build**

The pipeline builds the Flask Docker image from ./app/dockerfile. Every build produces a fresh image tagged with both latest and the Git commit SHA — so every deployment is traceable back to the exact commit that triggered it.

**Step 3 — Trivy Security Scan**

Before the image goes anywhere near production, Trivy scans it for known CVEs. It checks the base OS packages, Python dependencies, and application layers against its vulnerability database. CRITICAL and HIGH findings are reported in the pipeline logs. This is the security gate between "we built it" and "we deployed it."

**Step 4 — Push to ECR**

The scanned image is pushed to a private ECR repository. ECR also has scan_on_push enabled — so AWS runs its own vulnerability scan on arrival, independent of Trivy. Two scans, two opportunities to catch something before it runs on EC2.

**Step 5 — Deploy via SSM**

The pipeline sends shell commands to the EC2 instance using AWS Systems Manager — no SSH, no key pairs, no open port 22. SSM works through the IAM role attached to the instance. The commands pull the new image from ECR and restart the container.

---

## Key security decisions

**OIDC instead of access keys** — Long-lived AWS credentials in GitHub Secrets are a common source of cloud account compromise. OIDC eliminates them entirely. The GitHub Actions role gets a temporary token that expires after the pipeline run.

**Least privilege IAM roles** — The GitHub Actions role can only push to ECR and send SSM commands to this specific instance. The EC2 role can only pull from ECR and register with SSM.

**No SSH access** — Port 22 is not open in the security group. There are no key pairs attached to the instance. SSM is the only way in — and every SSM session is logged by AWS.

**EC2 only reachable through ALB** — The EC2 security group allows inbound traffic on port 5000 only from the ALB security group. Direct access to the instance IP is blocked.

**IMDSv2 enforced** — The EC2 instance requires a session token for metadata service requests, blocking SSRF attacks.

**Two-layer vulnerability scanning** — Trivy scans the image in the pipeline before push. ECR scans it again on arrival.

---

## Trivy scan results

Trivy scanned the Flask container image during deployment. The base image (Amazon Linux 2023) and Python dependencies (Flask 3.0.3, Gunicorn 22.0.0) returned clean results — no CRITICAL or HIGH vulnerabilities detected at time of deployment. Visible in pipeline logs under "Scan image with Trivy" step.

---

## Infrastructure

| Resource | Purpose |
|---|---|
| aws_ecr_repository | Private Docker image registry |
| aws_ecr_lifecycle_policy | Keeps last 5 images, deletes older ones |
| aws_iam_openid_connect_provider | Trusts GitHub Actions as identity provider |
| aws_iam_role (github_actions) | Role assumed by GitHub Actions via OIDC |
| aws_iam_role_policy | ECR push + SSM send command only |
| aws_iam_role (ec2) | Role attached to EC2 instance |
| aws_iam_role_policy_attachment (ssm) | SSM access without SSH |
| aws_iam_role_policy_attachment (ecr) | Pull images from ECR |
| aws_iam_instance_profile | Wraps EC2 role for instance use |
| aws_security_group (alb) | Port 80 from internet to ALB |
| aws_security_group (ec2) | Port 5000 from ALB only |
| aws_lb | Application Load Balancer |
| aws_lb_target_group | Routes to EC2 port 5000, health checks /health |
| aws_lb_listener | Port 80, forwards to target group |
| aws_lb_target_group_attachment | Registers EC2 with target group |
| aws_instance | EC2 t2.micro, Docker, SSM, IMDSv2 |

---

## Challenges solved

| Challenge | Solution |
|---|---|
| AWS credentials in GitHub pipeline | OIDC — temporary tokens, no stored keys |
| SSH key management for deployments | SSM — no keys, no open port 22 |
| Deploying untested images | Trivy scans before push, ECR scans on arrival |
| Container pulling from ECR | EC2 IAM role with ECR read-only permission |
| Direct EC2 exposure to internet | ALB as single entry point, SG blocks direct access |
| Terraform provider binary too large | .gitignore excludes .terraform/ folder |

---

## Project structure

```
flask-devsecops-aws-pipeline/
├── app/
│   ├── app.py              # Flask app — 2 endpoints
│   ├── dockerfile          # Gunicorn production server
│   └── requirements.txt    # flask==3.0.3, gunicorn==22.0.0
├── terraform/
│   ├── main.tf             # ECR, OIDC, IAM, EC2, ALB
│   ├── variables.tf        # Region, project, GitHub repo
│   ├── outputs.tf          # ALB DNS, ECR URL, EC2 ID, Role ARN
│   └── providers.tf        # AWS provider
├── .github/
│   └── workflows/
│       └── deploy.yml      # Full CI/CD pipeline
├── screenshots/            # Live deployment proof
├── .gitignore
└── README.md
```

---

## Deploy it yourself

```bash
git clone https://github.com/johntay379-hub/flask-devsecops-aws-pipeline.git
cd flask-devsecops-aws-pipeline/terraform
terraform init
terraform apply
```

Add these GitHub Secrets from terraform output:
- AWS_ROLE_ARN
- AWS_REGION
- ECR_REPOSITORY
- EC2_INSTANCE_ID

Then push to main — pipeline deploys automatically.

---

## Related projects

| Project | What it covers |
|---|---|
| [AWS CLI Security Framework](https://github.com/johntay379-hub/aws-end-to-end-security-framework) | IAM, S3, CloudTrail, VPC, EC2, CloudWatch, SNS |
| [Terraform Security Framework](https://github.com/johntay379-hub/terraform-aws-security-framework) | Same security model as Infrastructure as Code |
| [Zero Trust Security Platform](https://github.com/johntay379-hub/aws-zero-trust-security-platform) | ALB, Auto Scaling, AWS Config |
| [Secure CI/CD Pipeline](https://github.com/johntay379-hub/secure-cicd-pipeline) | Terraform pipeline with tfsec scanning |
| **Flask DevSecOps AWS Pipeline** | **Docker, ECR, OIDC, SSM, Trivy** |

---

## Author

**John Kamau** — AWS Cloud Engineer (Security Focused)
[github.com/johntay379-hub](https://github.com/johntay379-hub) · [linkedin.com/in/john-kamau-60ba53342](https://linkedin.com/in/john-kamau-60ba53342)

> The question this project answers: can you deploy a containerized application to AWS without ever touching a credential or an SSH key? Yes. This pipeline proves it.
