# CodeMentor AI - Troubleshooting Guide

## Common Issues and Solutions

### Infrastructure Issues

#### 1. Terraform State Lock Error

**Symptom**:
```
Error: Error acquiring the state lock
```

**Solution**:
```bash
# List locks
aws dynamodb scan --table-name ai-lab-terraform-locks

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### 2. EKS Cluster Creation Fails

**Symptom**: Terraform times out during cluster creation

**Causes**:
- IAM permissions insufficient
- VPC/subnet configuration issues

**Solution**:
```bash
# Check IAM permissions
aws sts get-caller-identity

# Verify VPC was created
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=ai-lab"

# Check Terraform logs
export TF_LOG=DEBUG
terraform apply
```

---

### Kubernetes Issues

#### 3. Nodes Not Ready

**Symptom**:
```bash
kubectl get nodes
# Shows NotReady status
```

**Solution**:
```bash
# Check node details
kubectl describe node <node-name>

# Common fixes:
# a) VPC-CNI issue
kubectl delete pod -n kube-system -l app=aws-node

# b) CoreDNS issue
kubectl rollout restart deployment coredns -n kube-system

# c) Check CloudWatch logs
aws eks describe-cluster --name ai-lab-eks
```

#### 4. Pods Stuck in Pending

**Symptom**: Pods remain in `Pending` state

**Diagnosis**:
```bash
kubectl describe pod -n ai-lab <pod-name>
```

**Common causes and fixes**:

**a) Insufficient CPU/Memory**:
```bash
# Check node resources
kubectl top nodes

# Scale up nodes
kubectl scale deployment <name> -n ai-lab --replicas=1
```

**b) PVC Not Bound**:
```bash
# Check PVC status
kubectl get pvc -n ai-lab

# Check storage class
kubectl get storageclass

# If missing, create:
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**c) Node Affinity Issues**:
```bash
# Check node labels
kubectl get nodes --show-labels

# Remove affinity temporarily for testing
kubectl edit deployment <name> -n ai-lab
```

---

### Application Issues

#### 5. Ollama Models Not Loading

**Symptom**: Init container fails or times out

**Diagnosis**:
```bash
kubectl logs -n ai-lab -l app=ollama -c model-loader
```

**Solutions**:

**a) Network timeout**:
```bash
# Check NAT Gateway
aws ec2 describe-nat-gateways | grep -A 5 ai-lab

# Test from pod
kubectl run test-pod --image=alpine --rm -it -- /bin/sh
# Inside pod:
wget -O- https://ollama.ai
```

**b) Insufficient memory**:
```bash
# Increase init container memory
kubectl edit deployment ollama -n ai-lab
# Change limits.memory to 6Gi
```

**c) Pre-download models manually**:
```bash
# Exec into running pod
kubectl exec -it -n ai-lab deployment/ollama -- /bin/bash

# Pull models
ollama pull tinyllama
ollama pull phi
ollama list
```

#### 6. Bolt Cannot Connect to Ollama

**Symptom**: Bolt UI loads but model requests fail

**Diagnosis**:
```bash
# Test connectivity
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
  curl -v http://ollama.ai-lab.svc.cluster.local:11434/api/tags
```

**Solutions**:

**a) Network Policy blocking**:
```bash
# Temporarily disable network policies
kubectl delete networkpolicy -n ai-lab --all

# Test again, then reapply
kubectl apply -f k8s/ai-lab/network-security.yaml
```

**b) DNS issues**:
```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- \
  nslookup ollama.ai-lab.svc.cluster.local
```

**c) Service not created**:
```bash
# Verify service
kubectl get svc -n ai-lab ollama

# Check endpoints
kubectl get endpoints -n ai-lab ollama
```

---

### Load Balancer Issues

#### 7. ALB Not Provisioning

**Symptom**: Ingress created but no ALB appears

**Diagnosis**:
```bash
# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress events
kubectl describe ingress -n ai-lab ai-lab-ingress
```

**Solutions**:

**a) IAM role not attached**:
```bash
# Verify service account annotation
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn

# Re-run Helm install with correct role
```

**b) Subnet tags missing**:
```bash
# Check subnet tags
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC_ID>"

# Required tags:
# Public: kubernetes.io/role/elb = 1
# Private: kubernetes.io/role/internal-elb = 1

# Add if missing:
aws ec2 create-tags --resources <SUBNET_ID> \
  --tags Key=kubernetes.io/role/elb,Value=1
```

**c) SecurityGroup limits**:
```bash
# Check SG quota
aws ec2 describe-account-attributes | grep max-security-groups-per-interface

# Delete unused SGs
aws ec2 describe-security-groups --filters "Name=tag:elbv2.k8s.aws/cluster,Values=ai-lab-eks"
```

---

### Performance Issues

#### 8. Slow Model Inference

**Symptom**: Responses take >10 seconds

**Diagnosis**:
```bash
# Check CPU/memory usage
kubectl top pods -n ai-lab

# Check resource limits
kubectl describe pod -n ai-lab -l app=ollama
```

**Solutions**:

**a) Resource constraints**:
```yaml
# Increase CPU/memory in ollama.yaml:
resources:
  requests:
    cpu: "2000m"
    memory: "4Gi"
  limits:
    cpu: "3000m"
    memory: "6Gi"
```

**b) Too many concurrent requests**:
```bash
# Check replica count
kubectl get deployment ollama -n ai-lab

# Scale up
kubectl scale deployment ollama -n ai-lab --replicas=3
```

**c) Use smaller model**:
- Switch from `phi` to `tinyllama`
- tinyllama is 3x faster

#### 9. HPA Not Scaling

**Symptom**: Bolt pods don't scale despite high load

**Diagnosis**:
```bash
kubectl get hpa -n ai-lab bolt-hpa -o yaml
kubectl describe hpa -n ai-lab bolt-hpa
```

**Solutions**:

**a) Metrics Server not running**:
```bash
kubectl get deployment metrics-server -n kube-system

# Reinstall if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**b) Resource requests not set**:
```bash
# Verify requests are defined
kubectl get deployment bolt -n ai-lab -o yaml | grep -A 5 resources
```

**c) HPA metrics unavailable**:
```bash
# Check metrics API
kubectl top pods -n ai-lab

# If error, restart metrics-server
kubectl rollout restart deployment metrics-server -n kube-system
```

---

### Cost Issues

#### 10. Unexpected High Costs

**Check AWS Cost Explorer**:
```bash
# Get current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter file://<(echo '{"Tags":{"Key":"Project","Values":["ai-lab"]}}')
```

**Common cost culprits**:
- ✅ EKS Control Plane: $72/month (fixed)
- ⚠️ EC2 on-demand instead of spot
- ⚠️ NAT Gateway data transfer
- ⚠️ ALB running 24/7

**Optimizations**:
```bash
# 1. Verify spot instances
kubectl get nodes -o json | jq '.items[].spec.providerID'
aws ec2 describe-instances --instance-ids <ID> | grep InstanceLifecycle
# Should show "spot"

# 2. Use VPC endpoints to reduce NAT costs
# Already configured in Terraform

# 3. Schedule downtime
kubectl scale deployment ollama -n ai-lab --replicas=0  # Nights
kubectl scale deployment bolt -n ai-lab --replicas=1    # Weekends
```

---

## Getting Help

### Collect Debug Information

```bash
#!/bin/bash
# debug-info.sh

echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== Pods ===" 
kubectl get pods -A

echo "=== Services ==="
kubectl get svc -A

echo "=== Ingress ==="
kubectl get ingress -A

echo "=== HPA ==="
kubectl get hpa -A

echo "=== Events ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

echo "=== Resource Usage ==="
kubectl top nodes
kubectl top pods -n ai-lab
```

### Contact Support

Include the above debug information plus:
- Terraform version
- kubectl version
- Error messages
- Steps to reproduce

---

## Quick Fixes Checklist

Before asking for help, try:

- [ ] Restart problematic pods: `kubectl rollout restart deployment <name> -n ai-lab`
- [ ] Check ALB controller: `kubectl logs -n kube-system deployment/aws-load-balancer-controller`
- [ ] Verify IAM roles: `kubectl get sa -A -o yaml | grep role-arn`
- [ ] Test network connectivity: `kubectl run curl-test --image=curlimages/curl --rm -it -- /bin/sh`
- [ ] Check resource quotas: `kubectl describe resourcequota -n ai-lab`
- [ ] Review CloudWatch logs
- [ ] Verify security groups allow traffic

---

**Last Updated**: 2026-01-07  
**Platform Version**: v1.0
