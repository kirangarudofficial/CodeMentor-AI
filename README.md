# CodeMentor AI
## Your AI-Powered Coding Companion

Industry-grade cloud-native platform for Computer Engineering students to explore AI-assisted coding with open-source language models.

## 🎯 Project Overview

**Project**: CodeMentor AI - Self-Hosted AI Coding Lab  
**Duration**: 5-10 days (temporary educational deployment)  
**Cost**: ~$62 for 10 days  
**Stack**: AWS EKS, Terraform, ArgoCD, Helm, Prometheus/Grafana

**Applications**:
- **Frontend**: Bolt (AI coding assistant)
- **Backend**: Ollama (TinyLlama, Phi-2 models)

## 📁 Project Structure

```
.
├── terraform/              # Infrastructure as Code
│   ├── modules/           # Reusable Terraform modules
│   │   ├── vpc/          # VPC, subnets, NAT gateway
│   │   ├── eks/          # EKS cluster configuration
│   │   └── iam/          # IAM roles and policies
│   ├── main.tf           # Root module
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values
│   ├── backend.tf        # S3 backend configuration
│   └── terraform.tfvars  # Variable values (gitignored)
│
├── k8s/                   # Kubernetes manifests
│   ├── namespaces/       # Namespace definitions
│   ├── core/             # Core components (ALB controller, metrics server)
│   ├── argocd/           # ArgoCD installation and apps
│   ├── monitoring/       # Prometheus & Grafana
│   ├── ai-lab/           # Application manifests
│   │   ├── ollama/      # Ollama deployment
│   │   └── bolt/        # Bolt frontend
│   └── ingress/          # ALB ingress configuration
│
├── helm-charts/           # Helm charts (for ArgoCD)
│   ├── ollama/
│   ├── bolt/
│   └── monitoring/
│
├── docs/                  # Documentation
│   ├── deployment-guide.md
│   ├── architecture.md
│   ├── troubleshooting.md
│   └── student-guide.md
│
└── scripts/               # Helper scripts
    ├── deploy.sh
    ├── teardown.sh
    └── validate.sh
```

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured
- Terraform >= 1.5
- kubectl >= 1.28
- helm >= 3.12

### Deployment

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Deploy infrastructure
terraform apply -auto-approve

# 3. Configure kubectl
aws eks update-kubeconfig --name ai-lab-eks --region us-east-1

# 4. Install core components
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/core/

# 5. Install ArgoCD
kubectl apply -f k8s/argocd/

# 6. Deploy applications via ArgoCD
# (ArgoCD will automatically sync from Git)
```

### Access

- **Bolt UI**: Get ALB URL with `kubectl get ingress -n ai-lab`
- **Grafana**: Port-forward with `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
- **ArgoCD**: Port-forward with `kubectl port-forward -n argocd svc/argocd-server 8080:443`

## 🛠️ Technology Stack

| Component | Technology |
|-----------|-----------|
| IaC | Terraform |
| Cloud | AWS (VPC, EKS, EC2, ALB, S3, IAM) |
| Container Orchestration | Kubernetes (EKS) |
| GitOps | ArgoCD |
| Package Manager | Helm |
| Monitoring | Prometheus + Grafana |
| Autoscaling | HPA, EC2 ASG |
| Backend | Ollama (CPU mode) |
| Frontend | Bolt |

## 📊 Architecture

Single-AZ deployment for cost optimization:
- **Public Subnet**: ALB, NAT Gateway
- **Private Subnet** (/26): EKS nodes (spot instances)
- **Applications**: Deployed via GitOps (ArgoCD)
- **Monitoring**: Prometheus + Grafana

## 💰 Cost Estimate

- EKS Control Plane: $72/month
- 3x t3.medium spot: ~$35/month
- ALB + NAT + Storage: ~$78/month
- **Total**: ~$185/month (~$62 for 10 days)

## 📚 Documentation

See `/docs` folder for:
- [Deployment Guide](docs/deployment-guide.md)
- [Architecture Details](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Student Guide](docs/student-guide.md)

## 🧹 Teardown

```bash
# Complete cleanup
./scripts/teardown.sh

# Or manually:
terraform destroy -auto-approve
```

## 📝 License

Educational use only - Computer Engineering Department

## 🤝 Contributing

This is a temporary educational project. For questions, contact the project maintainer.
