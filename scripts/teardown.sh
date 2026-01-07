#!/usr/bin/env bash
set -e

echo "🧹 CodeMentor AI - Teardown Script"
echo "====================================="

echo "⚠️  WARNING: This will destroy all resources!"
echo "             Cost will return to $0"
echo ""
read -p "Continue with teardown? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Teardown cancelled"
    exit 1
fi

# Delete Kubernetes resources first
echo ""
echo "🗑️  Deleting Kubernetes resources..."

kubectl delete ingress --all -n ai-lab 2>/dev/null || true
kubectl delete all --all -n ai-lab 2>/dev/null || true
kubectl delete pvc --all -n ai-lab 2>/dev/null || true
kubectl delete networkpolicy --all -n ai-lab 2>/dev/null || true

echo "⏳ Waiting for ALB to be deleted..."
sleep 60

# Uninstall Helm releases
echo ""
echo "📦 Uninstalling Helm releases..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true

# Destroy Terraform infrastructure
echo ""
echo "🏗️  Destroying Terraform infrastructure..."
cd terraform/
terraform destroy -auto-approve

echo ""
echo "========================================"
echo "✅ Teardown Complete!"
echo "========================================"
echo ""
echo "💰 Monthly cost is now: $0"
echo ""
echo "Optional cleanup (manual):"
echo "  aws s3 rm s3://ai-lab-terraform-state --recursive"
echo "  aws s3 rb s3://ai-lab-terraform-state"
echo "  aws dynamodb delete-table --table-name ai-lab-terraform-locks"
echo ""
