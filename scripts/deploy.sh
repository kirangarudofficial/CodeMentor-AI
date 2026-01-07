#!/usr/bin/env bash
set -e

echo "🚀 CodeMentor AI - Quick Deploy Script"
echo "========================================"

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not found. Install it first."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not found. Install it first."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found. Install it first."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Helm not found. Install it first."; exit 1; }
echo "✅ All prerequisites satisfied"

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
echo ""
echo "🔧 Initializing Terraform..."
terraform init

# Plan infrastructure
echo ""
echo "📊 Planning infrastructure..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
read -p "🤔 Deploy infrastructure? This will cost ~$185/month. (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Apply infrastructure
echo ""
echo "🏗️  Deploying infrastructure (15-20 minutes)..."
terraform apply tfplan

# Configure kubectl
echo ""
echo "⚙️  Configuring kubectl..."
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -json deployment_summary | jq -r '.region')
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Verify nodes
echo ""
echo "✅ Verifying nodes..."
kubectl get nodes

# Create namespaces
echo ""
echo "📦 Creating namespaces..."
kubectl apply -f ../k8s/namespaces/namespaces.yaml

# Install ALB Controller
echo ""
echo "🔌 Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

ALB_ROLE_ARN=$(terraform output -raw alb_controller_role_arn)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN

# Install Metrics Server
echo ""
echo "📊 Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Deploy applications
echo ""
echo "🤖 Deploying Ollama (this will take 5-10 minutes for model loading)..."
kubectl apply -f ../k8s/ai-lab/ollama/ollama.yaml

echo ""
echo "⏳ Waiting for Ollama pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ollama -n ai-lab --timeout=600s

echo ""
echo "💻 Deploying Bolt frontend..."
kubectl apply -f ../k8s/ai-lab/bolt/bolt.yaml

echo ""
echo "🌐 Deploying Ingress..."
kubectl apply -f ../k8s/ingress/ingress.yaml

echo ""
echo "🔒 Applying network policies..."
kubectl apply -f ../k8s/ai-lab/network-security.yaml

# Wait for ALB
echo ""
echo "⏳ Waiting for ALB to provision (2-3 minutes)..."
sleep 120

# Get ALB URL
ALB_URL=$(kubectl get ingress -n ai-lab -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

echo ""
echo "========================================"
echo "✅ Deployment Complete!"
echo "========================================"
echo ""
echo "📍 Access Bolt UI at: http://$ALB_URL"
echo ""
echo "🎓 Student Instructions:"
echo "   1. Open the URL above"
echo "   2. Go to Settings"
echo "   3. Set Base URL: http://ollama:11434"
echo "   4. Select Model: tinyllama or phi"
echo "   5. Start coding!"
echo ""
echo "📊 View logs: kubectl logs -n ai-lab -l app=ollama"
echo "📈 Check HPA: kubectl get hpa -n ai-lab"
echo ""
echo "⚠️  Remember to run ./teardown.sh when finished to avoid costs!"
echo ""
