#!/usr/bin/env bash
set -e

echo "🔍 CodeMentor AI - Validation Script"
echo "======================================"

errors=0

# Check Terraform files
echo ""
echo "📋 Validating Terraform code..."
cd terraform/

if terraform fmt -check -recursive; then
    echo "✅ Terraform formatting OK"
else
    echo "❌ Terraform formatting issues found"
    ((errors++))
fi

if terraform validate; then
    echo "✅ Terraform syntax OK"
else
    echo "❌ Terraform validation failed"
    ((errors++))
fi

cd ..

# Check Kubernetes manifests
echo ""
echo "📋 Validating Kubernetes manifests..."

for file in k8s/**/*.yaml; do
    if kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1; then
        echo "✅ $file syntax OK"
    else
        echo "❌ $file has syntax errors"
        ((errors++))
    fi
done

# Check required files
echo ""
echo "📋 Checking required files..."

required_files=(
    "README.md"
    "terraform/backend.tf"
    "terraform/main.tf"
    "terraform/variables.tf"
    "terraform/outputs.tf"
    "terraform/modules/vpc/main.tf"
    "terraform/modules/eks/main.tf"
    "terraform/modules/iam/main.tf"
    "k8s/namespaces/namespaces.yaml"
    "k8s/ai-lab/ollama/ollama.yaml"
    "k8s/ai-lab/bolt/bolt.yaml"
    "k8s/ingress/ingress.yaml"
    "docs/deployment-guide.md"
    "scripts/deploy.sh"
    "scripts/teardown.sh"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Found $file"
    else
        echo "❌ Missing $file"
        ((errors++))
    fi
done

# Check for secrets in code
echo ""
echo "🔒 Checking for potential secrets..."

if grep -r "AKIA" terraform/ k8s/ 2>/dev/null; then
    echo "⚠️  Possible AWS credentials found!"
    ((errors++))
fi

if grep -r "password.*=" terraform/ k8s/ | grep -v "CHANGE_ME" | grep -v "example" 2>/dev/null; then
    echo "⚠️  Hardcoded passwords found!"
    ((errors++))
fi

# Summary
echo ""
echo "======================================"
if [ $errors -eq 0 ]; then
    echo "✅ All validations passed!"
    exit 0
else
    echo "❌ Found $errors error(s)"
    exit 1
fi
