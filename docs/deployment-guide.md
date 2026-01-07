# CodeMentor AI - Deployment Guide

## Prerequisites

Before deploying the AI Lab Platform, ensure you have:

### Required Tools
- **AWS CLI** (v2.x): `aws --version`
- **Terraform** (>= 1.5): `terraform version`
- **kubectl** (>= 1.28): `kubectl version --client`
- **helm** (>= 3.12): `helm version`

### AWS Preparation

1. **Create S3 bucket for Terraform state**:
```bash
aws s3api create-bucket \
  --bucket ai-lab-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket ai-lab-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket ai-lab-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

2. **Create DynamoDB table for state locking**:
```bash
aws dynamodb create-table \
  --table-name ai-lab-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

3. **Configure AWS credentials**:
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region
```

---

## Phase 1: Infrastructure Deployment

### Step 1: Clone and Configure

```bash
cd terraform/

# Create terraform.tfvars file
cat > terraform.tfvars <<EOF
aws_region     = "us-east-1"
project_name   = "ai-lab"
cluster_name   = "ai-lab-eks"

# IMPORTANT: Change this to your university IP range
cluster_endpoint_public_access_cidrs = ["YOUR_IP/32"]

# Cost optimization
use_spot_instances = true
EOF
```

### Step 2: Initialize Terraform

```bash
terraform init
```

**Expected output**: Terraform initializes, downloads providers, configures S3 backend

### Step 3: Plan Infrastructure

```bash
terraform plan -out=tfplan
```

**Review**:
- VPC with single AZ
- EKS cluster with 3 nodes
- IAM roles for IRSA
- Estimated cost: ~$185/month

### Step 4: Apply Infrastructure

```bash
terraform apply tfplan
```

**Duration**: 15-20 minutes

**Outputs**:
```
vpc_id = "vpc-xxxxx"
cluster_name = "ai-lab-eks"
cluster_endpoint = "https://xxxxx.eks.us-east-1.amazonaws.com"
configure_kubectl = "aws eks update-kubeconfig --name ai-lab-eks --region us-east-1"
```

### Step 5: Configure kubectl

```bash
aws eks update-kubeconfig --name ai-lab-eks --region us-east-1

# Verify connection
kubectl get nodes
```

**Expected**: 3 nodes in `Ready` state

---

## Phase 2: Core Components

### Step 1: Create Namespaces

```bash
kubectl apply -f ../k8s/namespaces/namespaces.yaml
```

### Step 2: Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get ALB controller role ARN from Terraform output
ALB_ROLE_ARN=$(terraform output -raw alb_controller_role_arn)

# Install ALB controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=ai-lab-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN

# Verify
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Step 3: Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

---

## Phase 3: Application Deployment

### Step 1: Deploy Ollama Backend

```bash
kubectl apply -f ../k8s/ai-lab/ollama/ollama.yaml

# Wait for init container to pull models (5-10 minutes)
kubectl get pods -n ai-lab -w
```

**Check model loading**:
```bash
kubectl logs -n ai-lab -l app=ollama -c model-loader
```

### Step 2: Deploy Bolt Frontend

**Important**: Update the image in `bolt.yaml` first:
```bash
# Edit k8s/ai-lab/bolt/bolt.yaml
# Replace <YOUR_BOLT_IMAGE> with actual image

kubectl apply -f ../k8s/ai-lab/bolt/bolt.yaml

# Verify HPA
kubectl get hpa -n ai-lab
```

### Step 3: Deploy Ingress

```bash
kubectl apply -f ../k8s/ingress/ingress.yaml

# Wait for ALB provisioning (2-3 minutes)
kubectl get ingress -n ai-lab -w
```

### Step 4: Apply Network Policies

```bash
kubectl apply -f ../k8s/ai-lab/network-security.yaml

# Verify
kubectl get networkpolicy -n ai-lab
```

---

## Phase 4: Monitoring Stack

### Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create values file
cat > monitoring-values.yaml <<EOF
prometheus:
  prometheusSpec:
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 20Gi

grafana:
  enabled: true
  adminPassword: "CHANGE_ME_NOW"
  service:
    type: LoadBalancer

alertmanager:
  enabled: false
EOF

# Install
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml

# Get Grafana URL
kubectl get svc -n monitoring kube-prometheus-stack-grafana
```

---

## Phase 5: Verification

### Test 1: Check All Pods

```bash
kubectl get pods -A
```

**Expected**: All pods `Running`

### Test 2: Verify Ollama Models

```bash
kubectl exec -n ai-lab deployment/ollama -- ollama list
```

**Expected**:
```
NAME            SIZE    MODIFIED
tinyllama:latest    637MB   X minutes ago
phi:latest        1.6GB   X minutes ago
```

### Test 3: Test Ollama API

```bash
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -f http://ollama.ai-lab.svc.cluster.local:11434/api/tags
```

### Test 4: Access Bolt UI

```bash
ALB_URL=$(kubectl get ingress -n ai-lab -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "Access Bolt at: http://$ALB_URL"
```

Open in browser and verify:
1. Bolt UI loads
2. Go to Settings
3. Set base URL: `http://ollama:11434`
4. Select model: `tinyllama` or `phi`
5. Send test prompt

### Test 5: Verify HPA

```bash
kubectl get hpa -n ai-lab bolt-hpa
```

**Expected**: 
```
NAME       REFERENCE        TARGETS        MINPODS   MAXPODS   REPLICAS
bolt-hpa   Deployment/bolt  <X>%/<Y>%      3         10        3
```

---

## Student Access Instructions

1. **Access the Platform**:
   - URL: `http://<ALB_URL>` (get from above)
   - No authentication required

2. **Configure for Internal LLM**:
   - Click Settings ⚙️
   - Base URL: `http://ollama:11434`
   - Select Model: `tinyllama` (fast) or `phi` (better quality)
   - Click Save

3. **Start Coding**:
   - Ask: "Write a Python function to reverse a string"
   - Expect response in 1-3 seconds

---

## Troubleshooting

### Pods stuck in `Pending`

```bash
kubectl describe pod -n ai-lab <pod-name>
```

**Common causes**:
- Insufficient resources → check node capacity
- PVC not bound → check storage class

### ALB not provisioning

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Check**:
- IAM role attached correctly
- Subnets tagged properly

### Models not loading

```bash
kubectl logs -n ai-lab -l app=ollama -c model-loader
```

**Solution**: Increase init container timeout or check internet connectivity

---

## Teardown

**Complete cleanup**:

```bash
# Delete Kubernetes resources
kubectl delete ingress --all -n ai-lab
kubectl delete all --all -n ai-lab
helm uninstall kube-prometheus-stack -n monitoring

# Destroy infrastructure
cd terraform/
terraform destroy -auto-approve

# Clean S3 buckets (optional)
aws s3 rm s3://ai-lab-terraform-state --recursive
aws s3 rb s3://ai-lab-terraform-state

# Delete DynamoDB table
aws dynamodb delete-table --table-name ai-lab-terraform-locks
```

**Cost after teardown**: $0 ✅

---

## Next Steps

- Import into ArgoCD for GitOps
- Add custom Grafana dashboards
- Configure scheduled scaling
- Create student documentation

**Support**: Contact platform admin for issues
