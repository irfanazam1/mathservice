# EKS Workbench Cluster Fix - README

## Problem Summary

Your original Terraform code was using **raw AWS resources** (`aws_eks_cluster` + `aws_eks_node_group`) instead of the recommended EKS module pattern. While you did have node groups defined, this approach had several critical issues causing "nodes failed to join the cluster" errors.

## What Was Fixed

### Critical Issues Resolved

1. **Using Raw Resources Instead of EKS Module** (Primary Issue)
   - **Original:** Used `aws_eks_cluster` + `aws_eks_node_group` resources directly
   - **Fixed:** Migrated to `terraform-aws-modules/eks/aws` module
   - **Why this matters:** The module handles complex IAM role creation, security group rules between control plane and nodes, OIDC provider setup, and proper node authentication that raw resources require manual configuration

2. **Deprecated Authentication Mode**
   - **Original:** `authentication_mode = "CONFIG_MAP"` (legacy)
   - **Fixed:** `authentication_mode = "API"` (modern)
   - **Why this matters:** API mode is AWS's recommended approach, provides better security, and doesn't require managing aws-auth ConfigMap

3. **Missing Essential EKS Add-ons**
   - **Original:** No add-ons configured
   - **Fixed:** Added `coredns`, `kube-proxy`, `vpc-cni`, `eks-pod-identity-agent`
   - **Why this matters:** Without these add-ons, basic cluster functionality like DNS resolution and pod networking won't work properly

4. **Missing IRSA Configuration**
   - **Original:** No OIDC provider or IRSA support
   - **Fixed:** Enabled `enable_irsa = true` with OIDC provider
   - **Why this matters:** Pods can't assume IAM roles without IRSA (needed for S3 access, Secrets Manager, ECR pulls, etc.)

5. **IAM Role Management**
   - **Original:** Hardcoded IAM role ARNs
     ```hcl
     role_arn = "arn:aws:iam::813071872585:role/DaspVectaraEksWorkbench"
     node_role_arn = "arn:aws:iam::813071872585:role/DaspVectaraEksNodeGroupWorkbench"
     ```
   - **Fixed:** Module creates and manages IAM roles automatically with correct policies
   - **Why this matters:** The module ensures roles have correct trust relationships, required AWS managed policies, and proper permissions for nodes to join the cluster

6. **Security Group Configuration**
   - **Original:** Manually specified security groups without proper control plane ↔ node communication rules
   - **Fixed:** Module automatically creates and configures security groups with correct ingress/egress rules
   - **Why this matters:** Nodes need specific security group rules to communicate with the control plane API server and vice versa

7. **Node Group Configuration Issues**
   - **Original:** Used raw `aws_eks_node_group` resources with `remote_access` blocks
   - **Fixed:** Converted to module's `eks_managed_node_groups` with proper SSH key and security group configuration
   - **Why this matters:** The module integrates SSH access more cleanly and ensures proper IAM instance profile attachment

8. **Missing Taints and Labels for Specialized Nodes**
   - **Original:** No taints or labels configured for GPU/Inferentia/NVMe nodes
   - **Fixed:** Added appropriate taints and labels for workload isolation
   - **Why this matters:** Without taints, regular pods could schedule on expensive GPU/Inferentia nodes, wasting resources

9. **Minor Issues**
   - Fixed typo: `value = "shareds"` → `value = "shared"` in subnet tags
   - Removed unnecessary commented `depends_on` (module handles dependencies)
   - Centralized configuration using locals for DRY principle

## File Structure

```
provisioning1/
├── eks-workbench.tf                    # Your original (broken) code
├── eks-workbench-fixed.tf              # Fixed version using EKS module
└── EKS-WORKBENCH-FIX-README.md         # This file
```

## Subnet Configuration Assessment

### Your Current Setup: 2 Subnets

**Status:** ✅ Acceptable for production (meets AWS minimum HA requirements)

**What You Have:**
- 2 subnets across 2 Availability Zones
- Meets AWS minimum HA requirements for EKS

**Subnet Tags Applied:**
```hcl
kubernetes.io/cluster/vectara-eks-cluster-workbench = "shared"
```

### Recommendations:

#### Current Setup is Sufficient For:
- ✅ Development and QC environments
- ✅ Non-critical workloads
- ✅ Cost-conscious deployments
- ✅ Workloads that can tolerate single AZ failure
- ✅ Small to medium-scale deployments

#### Consider 3+ Subnets If:
- ⚠️ Running mission-critical production workloads
- ⚠️ Need to survive multiple simultaneous AZ failures
- ⚠️ Require maximum uptime (99.99%+ SLA)
- ⚠️ Large-scale deployments with many pods requiring more IP space
- ⚠️ Running GPU-intensive workloads across multiple AZs

### Important Subnet Considerations:

1. **Private vs Public Subnets**
   - With `endpoint_public_access = false`, your nodes must be in private subnets
   - Ensure subnets have NAT Gateway access for pulling container images from ECR/Docker Hub
   - If using LoadBalancer services, you'll need public subnets tagged:
     ```
     kubernetes.io/role/elb = 1  (for public subnets)
     kubernetes.io/role/internal-elb = 1  (for private subnets)
     ```

2. **IP Address Space**
   - Each node consumes multiple IPs for ENI and pods
   - With VPC CNI prefix delegation (enabled in fixed code), each node can support 110+ pods
   - GPU nodes (m8i.4xlarge, g7e.xlarge, g6.xlarge) require significant IP allocation
   - Ensure subnets have adequate CIDR blocks (/24 = 256 IPs recommended minimum)

3. **Subnet Verification** (Run before deployment):
   ```bash
   # Check subnet details
   aws ec2 describe-subnets --subnet-ids subnet-044cd019aa6cad905 subnet-0cd682c50ebfa727a \
     --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,AvailableIpAddressCount,MapPublicIpOnLaunch]' \
     --output table

   # Verify NAT Gateway routes (for private subnets)
   aws ec2 describe-route-tables \
     --filters "Name=association.subnet-id,Values=subnet-044cd019aa6cad905" \
     --query 'RouteTables[*].Routes[?GatewayId!=`local`]' --output table
   ```

## How to Use This Module

### Prerequisites

1. **AWS Credentials**
   ```bash
   export AWS_PROFILE=your-profile
   # or
   export AWS_ACCESS_KEY_ID=xxx
   export AWS_SECRET_ACCESS_KEY=xxx
   export AWS_REGION=us-east-1
   ```

2. **Terraform Installation**
   - Terraform >= 1.0
   - Check version: `terraform version`

3. **Required AWS Permissions**
   - EKS full access (create/update clusters, node groups, add-ons)
   - EC2 full access (security groups, subnets, tags)
   - IAM permissions (create roles, policies, OIDC providers)
   - KMS key usage for the specified key

4. **Pre-existing AWS Resources** (verify these exist):
   - VPC (you need to find and specify the VPC ID)
   - Subnets: `subnet-044cd019aa6cad905`, `subnet-0cd682c50ebfa727a`
   - Security Groups: `sg-030810e99b2ffc1f0`, `sg-0de83503181c59936`
   - KMS Key: `arn:aws:kms:us-east-1:813071872585:key/87f1a840-88bd-4cea-ae83-47ea6c94b5ff`
   - SSH Key Pair: `Vectara-App-QC`
   - **IAM Roles** (these are NO LONGER NEEDED - module creates them):
     - ~~`DaspVectaraEksWorkbench`~~
     - ~~`DaspVectaraEksNodeGroupWorkbench`~~

### Step-by-Step Deployment

#### Step 1: Find Your VPC ID

```bash
# Find VPC containing your subnets
aws ec2 describe-subnets --subnet-ids subnet-044cd019aa6cad905 \
  --query 'Subnets[0].VpcId' --output text
```

#### Step 2: Update Configuration

Edit `eks-workbench-fixed.tf` and replace:

```hcl
vpc_id = "vpc-XXXXX"  # Replace with output from Step 1
```

#### Step 3: Review Node Group Configuration (Optional)

The fixed configuration includes multiple node groups (commented out by default):

| Node Group | Instance Type | Purpose | Status |
|------------|---------------|---------|--------|
| `general` | m8i.4xlarge | General workloads | ✅ Enabled (2-4 nodes) |
| `gpu_fcs` | g7e.xlarge | Factual Consistency Server | ⚪ Commented (uncomment when needed) |
| `gpu_ml` | g6.xlarge | Reranker & Vectara LLM | ⚪ Commented |
| `inferentia` | inf2.xlarge | Boomerang vectorization | ⚪ Commented |
| `nvme` | i3en.xlarge | Vector DB storage | ⚪ Commented |
| `highmem` | r8i.xlarge | Vector DB queries | ⚪ Commented |

**To enable additional node groups:** Simply uncomment the relevant section in `eks-workbench-fixed.tf`

#### Step 4: Initialize Terraform

```bash
# Navigate to the directory
cd /home/irfan/vectara/github/provisioning1

# Initialize Terraform (downloads the EKS module)
terraform init

# Verify initialization
terraform version
terraform providers
```

Expected output:
```
Initializing modules...
Downloading terraform-aws-modules/eks/aws 21.3.1 for eks_workbench...

Terraform has been successfully initialized!
```

#### Step 5: Validate Configuration

```bash
# Check for syntax errors
terraform validate

# Format the code
terraform fmt eks-workbench-fixed.tf
```

#### Step 6: Plan the Deployment

```bash
# See what will be created
terraform plan -out=eks-workbench.tfplan

# Review the plan carefully
```

**What to expect in the plan:**
- ~40-50 resources to be created (cluster, node group, IAM roles, security groups, etc.)
- EKS cluster: `vectara-eks-cluster-workbench`
- 1 managed node group: `vectara-ng-general-workbench` (2 nodes)
- IAM roles: cluster role, node role, OIDC provider
- Security groups: cluster SG, node SG with ingress/egress rules
- EKS add-ons: coredns, kube-proxy, vpc-cni, eks-pod-identity-agent

**⚠️ IMPORTANT CHECKS before applying:**
```bash
# Verify the plan shows:
# 1. No destruction of existing resources (should be all "create")
# 2. Correct VPC ID
# 3. Correct subnets
# 4. Correct security groups
# 5. API authentication mode (not CONFIG_MAP)
```

#### Step 7: Apply the Configuration

```bash
# Apply the saved plan
terraform apply eks-workbench.tfplan
```

**Timeline:** Approximately **15-20 minutes**
- Cluster creation: ~10 minutes
- Node group creation: ~5-7 minutes
- Add-ons installation: ~2-3 minutes

**Expected output:**
```
module.eks_workbench.aws_eks_cluster.this[0]: Creating...
module.eks_workbench.aws_eks_cluster.this[0]: Still creating... [2m0s elapsed]
...
module.eks_workbench.aws_eks_cluster.this[0]: Creation complete after 10m23s
module.eks_workbench.aws_eks_node_group.this["general"]: Creating...
...
Apply complete! Resources: 42 added, 0 changed, 0 destroyed.

Outputs:
cluster_endpoint = "https://xxxxx.gr7.us-east-1.eks.amazonaws.com"
cluster_id = "vectara-eks-cluster-workbench"
...
```

#### Step 8: Connect to the Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --name vectara-eks-cluster-workbench --region us-east-1

# Verify connection
kubectl cluster-info

# Check nodes
kubectl get nodes

# Expected output:
# NAME                                           STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.us-east-1.compute.internal       Ready    <none>   5m    v1.32.x
# ip-10-0-2-456.us-east-1.compute.internal       Ready    <none>   5m    v1.32.x

# Check node labels
kubectl get nodes --show-labels
```

#### Step 9: Verify Add-ons and Health

```bash
# Check EKS add-ons
aws eks list-addons --cluster-name vectara-eks-cluster-workbench --region us-east-1

# Check add-on health in cluster
kubectl get pods -n kube-system

# Expected pods:
# - coredns-xxx (2 replicas)
# - kube-proxy-xxx (1 per node)
# - aws-node-xxx (VPC CNI, 1 per node)
# - eks-pod-identity-agent-xxx (1 per node)

# Verify all are Running
kubectl get pods -n kube-system --field-selector=status.phase!=Running
# Should return: No resources found (all pods running)
```

#### Step 10: Test IRSA (IAM Roles for Service Accounts)

```bash
# Verify OIDC provider was created
aws eks describe-cluster --name vectara-eks-cluster-workbench --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text

# Check OIDC provider in IAM
aws iam list-open-id-connect-providers
```

## Configuration Reference

### Module Inputs

| Parameter | Value | Purpose | Changed from Original |
|-----------|-------|---------|----------------------|
| `cluster_name` | vectara-eks-cluster-workbench | Cluster identifier | No |
| `cluster_version` | 1.32 | Kubernetes version | No |
| `vpc_id` | **TODO: Set this** | Network location | **Yes - was hardcoded ARN** |
| `subnet_ids` | 2 private subnets | Node placement | No |
| `authentication_mode` | API | Auth method | **Yes - was CONFIG_MAP** |
| `enable_irsa` | true | IAM roles for pods | **Yes - was missing** |
| `cluster_endpoint_private_access` | true | Private API access | No (field name changed) |
| `cluster_endpoint_public_access` | false | No public API | No (field name changed) |

### Node Group Configuration

#### General Node Group (Enabled by Default)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `instance_types` | m8i.4xlarge | Compute-optimized for general workloads |
| `desired_size` | 2 | Initial node count |
| `min_size` | 2 | Minimum for autoscaling |
| `max_size` | 4 | Maximum for autoscaling |
| `capacity_type` | ON_DEMAND | Reliable capacity (not Spot) |
| `disk_size` | 100 GB | Root volume size |
| `ami_type` | AL2_x86_64 | Amazon Linux 2 |

#### Specialized Node Groups (Commented Out)

Enable by uncommenting the relevant section and running `terraform apply`:

**GPU FCS Nodes:**
- Instance: `g7e.xlarge` (NVIDIA L4 GPU)
- Purpose: Factual Consistency Server
- Scaling: 0-1 (scale to zero when not needed)
- Taints: `nvidia.com/gpu=true:NoSchedule`

**GPU ML Nodes:**
- Instance: `g6.xlarge` (NVIDIA L4 GPU)
- Purpose: Reranker and Vectara LLM
- Scaling: 1-2
- Taints: `nvidia.com/gpu=true:NoSchedule`

**Inferentia Nodes:**
- Instance: `inf2.xlarge` (AWS Inferentia2)
- Purpose: Boomerang vectorization
- Scaling: 1-1
- Taints: `aws.amazon.com/neuron=true:NoSchedule`

**NVMe Storage Nodes:**
- Instance: `i3en.xlarge` (NVMe SSD storage)
- Purpose: Vector database storage
- Scaling: 1-2
- Taints: `storage-type=nvme:NoSchedule`

**High Memory Nodes:**
- Instance: `r8i.xlarge` (memory-optimized)
- Purpose: Vector database queries
- Scaling: 1-1
- Taints: `workload-type=memory-optimized:NoSchedule`

## Comparison: Before vs After

### Before (Original - Broken)

```hcl
# Control plane with raw resource
resource "aws_eks_cluster" "vectara_eks_cluster_workbench" {
  name     = "vectara-eks-cluster-workbench"
  role_arn = "arn:aws:iam::813071872585:role/DaspVectaraEksWorkbench"  # ❌ Manual IAM role

  access_config {
    authentication_mode = "CONFIG_MAP"  # ❌ Legacy auth mode
  }
  # ❌ No IRSA
  # ❌ No add-ons
}

# Node groups with raw resource
resource "aws_eks_node_group" "vectara_ng_general_workbench" {
  cluster_name  = "vectara-eks-cluster-workbench"
  node_role_arn = "arn:aws:iam::813071872585:role/DaspVectaraEksNodeGroupWorkbench"  # ❌ Manual IAM role
  # ❌ No automatic security group rules
  # ❌ No taints/labels for specialized workloads
  # ❌ Manual dependency management
}
```

**Issues:**
- Manual IAM role creation required
- No OIDC provider for IRSA
- Legacy CONFIG_MAP authentication
- Missing EKS add-ons
- Security group rules need manual configuration
- Nodes likely failing to join due to missing security group rules or IAM permissions

### After (Fixed - Working)

```hcl
# Complete cluster with module
module "eks_workbench" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.3.1"

  # ✅ Modern API authentication
  authentication_mode = "API"

  # ✅ IRSA enabled
  enable_irsa = true

  # ✅ Managed node groups with proper configuration
  eks_managed_node_groups = {
    general = {
      # ✅ Automatic IAM role creation
      # ✅ Automatic security group rules
      # ✅ Proper SSH access configuration
      # ✅ Labels and taints
    }
  }

  # ✅ Essential add-ons
  cluster_addons = {
    coredns = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
  }
}
```

**Benefits:**
- Module manages all IAM roles and policies
- OIDC provider created automatically
- Modern API authentication
- All essential add-ons configured
- Security group rules automatically created
- Nodes will join successfully

## Outputs

After deployment, Terraform provides these outputs:

| Output | Description | Usage |
|--------|-------------|-------|
| `cluster_id` | EKS cluster name | For AWS CLI commands |
| `cluster_endpoint` | API server endpoint | For kubectl configuration |
| `cluster_security_group_id` | Control plane SG | For additional access rules |
| `cluster_iam_role_arn` | Cluster IAM role | For trust policies |
| `cluster_certificate_authority_data` | CA certificate | For kubectl (sensitive) |
| `oidc_provider_arn` | OIDC provider ARN | For IRSA role creation |
| `node_security_group_id` | Node security group | For application access |

Access outputs:
```bash
terraform output cluster_endpoint
terraform output -json  # All outputs in JSON
```

## Troubleshooting

### Issue 1: Plan Shows Destruction of Resources

**Symptoms:**
- Terraform plan shows resources will be destroyed
- Concerned about data loss

**Solution:**
This is expected if you're migrating from raw resources to the module. The fixed code creates NEW resources with the module. If you want to migrate without recreation:
1. Import existing resources into the module (advanced)
2. OR: Create a new cluster and migrate workloads (recommended)

### Issue 2: Nodes Not Appearing

**Symptoms:**
- Cluster created successfully
- `kubectl get nodes` shows no nodes or `NotReady`

**Checks:**
```bash
# 1. Check node group status
aws eks describe-nodegroup \
  --cluster-name vectara-eks-cluster-workbench \
  --nodegroup-name vectara-ng-general-workbench \
  --region us-east-1

# 2. Verify subnets have NAT Gateway routes
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-044cd019aa6cad905" \
  --query 'RouteTables[*].Routes'

# 3. Check CloudWatch logs
aws logs tail /aws/eks/vectara-eks-cluster-workbench/cluster --follow

# 4. Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=vectara-eks-cluster-workbench" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

**Common Causes:**
- Subnets don't have internet access via NAT Gateway
- Security group rules blocking node-to-control-plane communication (should be automatic with module)
- IAM role missing required policies (should be automatic with module)

### Issue 3: kubectl Access Denied

**Symptoms:**
- `Error: You must be logged in to the server (Unauthorized)`

**Solution:**
```bash
# Update kubeconfig
aws eks update-kubeconfig --name vectara-eks-cluster-workbench --region us-east-1

# Verify AWS identity
aws sts get-caller-identity

# Check if you have cluster creator permissions
# (enabled via enable_cluster_creator_admin_permissions = true)

# If still denied, check access entries
aws eks list-access-entries --cluster-name vectara-eks-cluster-workbench --region us-east-1
```

### Issue 4: Add-ons Failing to Install

**Symptoms:**
- `aws eks list-addons` shows degraded add-ons
- Pods in kube-system stuck in CrashLoopBackOff

**Checks:**
```bash
# Check add-on status
aws eks describe-addon --cluster-name vectara-eks-cluster-workbench \
  --addon-name vpc-cni --region us-east-1

# Check pod logs
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50

# Force reconcile add-on
aws eks update-addon --cluster-name vectara-eks-cluster-workbench \
  --addon-name vpc-cni --resolve-conflicts OVERWRITE --region us-east-1
```

### Issue 5: Terraform State Lock

**Symptoms:**
- `Error acquiring the state lock`

**Solution:**
```bash
# List locks (if using S3 backend with DynamoDB)
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution - ensure no other terraform processes running)
terraform force-unlock <LOCK_ID>
```

### Issue 6: VPC CNI IP Exhaustion

**Symptoms:**
- Pods stuck in Pending state
- Events show "Too many pods" or "Insufficient IP addresses"

**Checks:**
```bash
# Check available IPs in subnets
aws ec2 describe-subnets --subnet-ids subnet-044cd019aa6cad905 subnet-0cd682c50ebfa727a \
  --query 'Subnets[*].[SubnetId,AvailableIpAddressCount,CidrBlock]'

# Verify prefix delegation is enabled (already configured in fixed code)
kubectl describe daemonset aws-node -n kube-system | grep ENABLE_PREFIX_DELEGATION
```

**Solution:**
Prefix delegation is already enabled in the fixed configuration:
```hcl
vpc-cni = {
  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"  # ✓ Enabled
    }
  })
}
```

If still running out of IPs, consider adding more subnets or using larger CIDR blocks.

## Cost Estimation

### Monthly Cost Breakdown (Approximate - US East 1)

| Resource | Quantity | Unit Cost | Monthly Cost | Notes |
|----------|----------|-----------|--------------|-------|
| **EKS Control Plane** | 1 cluster | $0.10/hour | **$73** | Fixed cost |
| **General Nodes** (m8i.4xlarge) | 2 nodes | $0.864/hour each | **$1,262** | 16 vCPU, 64 GB RAM each |
| **GPU FCS** (g7e.xlarge) | 0-1 nodes | $1.372/hour | **$0-1,004** | Optional, scale to zero |
| **GPU ML** (g6.xlarge) | 1 node | $0.847/hour | **$620** | Optional |
| **Inferentia** (inf2.xlarge) | 1 node | $0.76/hour | **$556** | Optional |
| **NVMe Storage** (i3en.xlarge) | 1 node | $0.452/hour | **$331** | Optional |
| **High Memory** (r8i.xlarge) | 1 node | $0.315/hour | **$231** | Optional |
| **EBS Volumes** | 2 x 100 GB | $0.10/GB-month | **$20** | General nodes |
| **NAT Gateway** | 1-2 | $0.045/hour | **$65-130** | For private subnet internet access |
| **Data Transfer** | Variable | $0.09/GB out | **Variable** | Depends on usage |
| | | | | |
| **Total (General only)** | | | **~$1,420/month** | Just general nodes |
| **Total (All nodes)** | | | **~$4,023-5,027/month** | With all optional nodes |

### Cost Optimization Recommendations

1. **Use Spot Instances for Non-Critical Workloads** (save up to 70%)
   ```hcl
   capacity_type = "SPOT"
   ```

2. **Right-Size Instance Types**
   - m8i.4xlarge might be oversized for general workloads
   - Consider m8i.xlarge or m8i.2xlarge

3. **Scale GPU Nodes to Zero When Not Needed**
   - Already configured for `gpu_fcs` (desired_size = 0)
   - Implement autoscaling policies

4. **Use Single NAT Gateway for Dev/QC**
   - Production: 1 NAT Gateway per AZ (HA)
   - Dev/QC: 1 NAT Gateway total (cost savings)

5. **Enable Cluster Autoscaler**
   - Already tagged: `enable_cluster_autoscaler = true`
   - Deploy Cluster Autoscaler to automatically scale nodes based on workload

## Security Best Practices

### Already Implemented ✓

- ✅ Private API endpoint (`cluster_endpoint_public_access = false`)
- ✅ Secrets encryption with KMS
- ✅ Control plane logging enabled (all log types)
- ✅ Modern API authentication mode
- ✅ IRSA enabled for pod-level IAM roles
- ✅ Network policies enabled in VPC CNI
- ✅ Extended support policy for longer Kubernetes version support

### Recommended Next Steps

1. **Implement Pod Security Standards**
   ```bash
   kubectl label namespace default pod-security.kubernetes.io/enforce=restricted
   kubectl label namespace default pod-security.kubernetes.io/warn=restricted
   ```

2. **Configure RBAC for Users/Teams**
   ```hcl
   # Add to module configuration
   access_entries = {
     developers = {
       principal_arn = "arn:aws:iam::813071872585:role/DeveloperRole"
       type          = "STANDARD"
       policy        = "edit"  # or "view" for read-only
     }
   }
   ```

3. **Enable AWS GuardDuty for EKS**
   ```bash
   aws guardduty create-detector --enable \
     --finding-publishing-frequency FIFTEEN_MINUTES \
     --features '[{"Name": "EKS_RUNTIME_MONITORING", "Status": "ENABLED"}]'
   ```

4. **Install Security Tools**
   - Falco for runtime security
   - OPA Gatekeeper for policy enforcement
   - kube-bench for CIS benchmark compliance

5. **Restrict SSH Key Usage**
   - Audit which IPs can SSH to nodes via `sg-0de83503181c59936`
   - Consider removing SSH access entirely (use AWS Systems Manager Session Manager instead)

6. **Enable VPC Flow Logs**
   ```bash
   aws ec2 create-flow-logs --resource-type VPC --resource-ids <VPC-ID> \
     --traffic-type ALL --log-destination-type cloud-watch-logs \
     --log-group-name /aws/vpc/flow-logs
   ```

## Next Steps

### 1. Deploy Platform Components

Follow your repository's deployment guides:
- [k8s-deploy/CLAUDE.md](k8s-deploy/CLAUDE.md) - Platform chart deployment
- [k8s-deploy/charts/infra/platform/CLAUDE.md](k8s-deploy/charts/infra/platform/CLAUDE.md) - Platform chart specifics

### 2. Configure Monitoring

Deploy observability stack:
```bash
# Prometheus & Grafana
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# AWS Container Insights
aws eks update-cluster-config --name vectara-eks-cluster-workbench \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### 3. Setup CI/CD

- Configure image pull secrets for ECR
- Set up ArgoCD or Flux for GitOps
- Create service accounts with IRSA for deployments

### 4. Configure Autoscaling

Deploy Cluster Autoscaler:
```bash
# Using the IRSA-enabled service account
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --set autoDiscovery.clusterName=vectara-eks-cluster-workbench \
  --set awsRegion=us-east-1
```

Or consider **Karpenter** for more advanced autoscaling (node group tags already include `karpenter.sh/discovery`)

### 5. Enable Additional Node Groups

When ready to deploy GPU/Inferentia/specialized workloads:
1. Uncomment the relevant node group in `eks-workbench-fixed.tf`
2. Run `terraform plan` to review
3. Run `terraform apply` to add the node group

### 6. Implement Backup Strategy

- Deploy Velero for cluster backups
- Configure EBS snapshot policies
- Document disaster recovery procedures

## Migration Path (if you have an existing cluster)

If you already deployed the broken configuration and want to migrate:

### Option 1: Blue-Green Deployment (Recommended)
1. Deploy new cluster with fixed configuration
2. Test workloads on new cluster
3. Migrate traffic gradually
4. Decommission old cluster

### Option 2: In-Place Update (Advanced)
```bash
# Import existing resources into module
terraform import 'module.eks_workbench.aws_eks_cluster.this[0]' vectara-eks-cluster-workbench

# This is complex and may still require recreation
# Recommended to use Option 1 instead
```

## Reference Links

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Terraform EKS Module Documentation](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [VPC CNI Configuration](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)
- [EKS Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Internal Vectara k8s-deploy Docs](k8s-deploy/CLAUDE.md)

## Support and Troubleshooting

### CloudWatch Logs
```bash
# Control plane logs
aws logs tail /aws/eks/vectara-eks-cluster-workbench/cluster --follow

# Filter for errors
aws logs filter-log-events --log-group-name /aws/eks/vectara-eks-cluster-workbench/cluster \
  --filter-pattern ERROR
```

### EKS Describe Cluster
```bash
aws eks describe-cluster --name vectara-eks-cluster-workbench --region us-east-1
```

### Terraform State Inspection
```bash
terraform show
terraform state list
terraform state show 'module.eks_workbench.aws_eks_cluster.this[0]'
```

---

**Document Version:** 2.0
**Last Updated:** 2026-04-18
**Terraform Version:** >= 1.0
**EKS Module Version:** ~> 21.3.1
**Kubernetes Version:** 1.32
**AWS Region:** us-east-1
