################################################################################
# EKS Cluster - vectara-eks-cluster-workbench
#
# This configuration uses the official terraform-aws-modules/eks module
# to create a production-ready EKS cluster with multiple managed node groups
# for different workload types (general, GPU, Inferentia, NVMe, high-memory).
#
# FIXES APPLIED:
# 1. Migrated from raw aws_eks_cluster + aws_eks_node_group resources to the module
# 2. Changed authentication_mode from CONFIG_MAP to API (modern approach)
# 3. Added essential EKS addons (coredns, vpc-cni, kube-proxy, pod-identity-agent)
# 4. Enabled IRSA for pod-level IAM role assignment
# 5. Properly configured node group SSH access and security groups
# 6. Added taints and labels for specialized node groups
################################################################################

locals {
  cluster_name = "vectara-eks-cluster-workbench"

  # Common tags for all node groups
  ng_common_tags = {
    Lifecycle   = "QC"
    AppID       = "AR5852-QC003"
    Project     = "Vectara Platform Deployment"
    BUSub       = "Data Analytics"
    RunSchedule = "Weekday8to6"
  }

  # Subnets for cluster and node groups
  subnet_ids = [
    "subnet-044cd019aa6cad905",
    "subnet-0cd682c50ebfa727a",
  ]

  # SSH key for node access
  ssh_key_name = "Vectara-App-QC"
}

# Subnet tags required for EKS cluster discovery
# IMPORTANT: These tags allow EKS to discover and use the subnets for load balancers
resource "aws_ec2_tag" "vectara_eks_cluster_workbench_subnet_tags" {
  for_each = toset(local.subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "shared"
}

# Main EKS Cluster Module
module "eks_workbench" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.3.1"

  name               = local.cluster_name
  kubernetes_version = "1.32"

  # VPC Configuration
  # RECOMMENDATION: For production EKS clusters, you should have:
  # - At least 2 subnets in different Availability Zones (for HA) ✓
  # - Private subnets for nodes (recommended for security)
  # - Public subnets for load balancers (if using LoadBalancer services)
  # - Minimum /24 CIDR per subnet recommended (provides ~250 IPs)
  #
  # Your current setup with 2 subnets meets minimum HA requirements, but consider:
  # 1. Using 3+ AZs for better fault tolerance
  # 2. Ensuring subnets are private if endpoint_public_access = false
  # 3. Having sufficient IP space for pod networking (ENI considerations)
  # 4. Separate public subnets if you need internet-facing load balancers
  # 5. For large clusters with GPU nodes, ensure adequate IP space per subnet
  vpc_id     = "vpc-XXXXX" # TODO: Replace with your actual VPC ID
  subnet_ids = local.subnet_ids

  # Endpoint Configuration
  endpoint_private_access = true
  endpoint_public_access  = false

  # Additional Security Groups for Control Plane Access
  # These allow the control plane to communicate with other network resources
  additional_security_group_ids = [
    "sg-030810e99b2ffc1f0",
    "sg-0de83503181c59936",
  ]

  # Authentication - use modern API mode instead of legacy CONFIG_MAP
  # IMPORTANT: Your original code used CONFIG_MAP (legacy). This uses API mode.
  # With API mode, you manage access via access_entries instead of aws-auth ConfigMap
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Enable IAM Roles for Service Accounts (IRSA)
  # Required for pods to assume IAM roles (e.g., S3 access, Secrets Manager, etc.)
  enable_irsa                     = true
  include_oidc_root_ca_thumbprint = false

  # Cluster Encryption Configuration

  # Control Plane Logging

  # Support Policy

  # EKS Managed Node Groups
  # Multiple node groups for different workload types
  eks_managed_node_groups = {
    # General Purpose Nodes - Main workload nodes
    general = {
      name = "vectara-ng-general-workbench"

      # Node sizing
      desired_size = 2
      min_size     = 2
      max_size     = 4

      # Instance configuration
      instance_types = ["m8i.4xlarge"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 100

      # Use AL2 (Amazon Linux 2) as specified in your original code
      ami_type = "AL2_x86_64"

      # SSH Access
      key_name = local.ssh_key_name

      # Apply additional security group for SSH access
      vpc_security_group_ids = ["sg-0de83503181c59936"]

      # Deploy nodes in specified subnets
      subnet_ids = local.subnet_ids

      # Enable cluster autoscaler support
      enable_cluster_autoscaler = true

      # Labels for workload scheduling
      labels = {
        workload-type = "general"
        node-group    = "general"
      }

      # Tags
      tags = merge(local.ng_common_tags, {
        Name        = "vectara-ng-general-workbench"
        Description = "General purpose nodes for Vectara shared services"
      })
    }

    # GPU Nodes for FCS (Factual Consistency Server) - Scale to zero when not needed
    # UNCOMMENT when ready to deploy
    # gpu_fcs = {
    #   name = "vectara-ng-gpu-fcs-workbench"
    #
    #   desired_size = 0
    #   min_size     = 0
    #   max_size     = 1
    #
    #   instance_types = ["g7e.xlarge"]
    #   capacity_type  = "ON_DEMAND"
    #   disk_size      = 200
    #   ami_type       = "AL2_x86_64_GPU"
    #   key_name       = local.ssh_key_name
    #
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type = "gpu"
    #     node-group    = "gpu-fcs"
    #     "nvidia.com/gpu" = "true"
    #   }
    #
    #   taints = {
    #     gpu = {
    #       key    = "nvidia.com/gpu"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    #
    #   tags = merge(local.ng_common_tags, {
    #     Name        = "vectara-ng-gpu-fcs-workbench"
    #     Description = "GPU node for Factual Consistency Server"
    #   })
    # }

    # GPU Nodes for ML (Reranker and Vectara LLM)
    # UNCOMMENT when ready to deploy
    # gpu_ml = {
    #   name = "vectara-ng-gpu-ml-workbench"
    #
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 2
    #
    #   instance_types = ["g6.xlarge"]
    #   capacity_type  = "ON_DEMAND"
    #   disk_size      = 200
    #   ami_type       = "AL2_x86_64_GPU"
    #   key_name       = local.ssh_key_name
    #
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type = "gpu"
    #     node-group    = "gpu-ml"
    #     "nvidia.com/gpu" = "true"
    #   }
    #
    #   taints = {
    #     gpu = {
    #       key    = "nvidia.com/gpu"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    #
    #   tags = merge(local.ng_common_tags, {
    #     Name        = "vectara-ng-gpu-ml-workbench"
    #     Description = "GPU nodes for Reranker and Vectara LLM"
    #   })
    # }

    # Inferentia Nodes for Boomerang Vectorization
    # UNCOMMENT when ready to deploy
    # inferentia = {
    #   name = "vectara-ng-inferentia-workbench"
    #
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 1
    #
    #   instance_types = ["inf2.xlarge"]
    #   capacity_type  = "ON_DEMAND"
    #   disk_size      = 100
    #   ami_type       = "AL2_x86_64"
    #   key_name       = local.ssh_key_name
    #
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type = "inferentia"
    #     node-group    = "inferentia"
    #     "aws.amazon.com/neuron" = "true"
    #   }
    #
    #   taints = {
    #     inferentia = {
    #       key    = "aws.amazon.com/neuron"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    #
    #   tags = merge(local.ng_common_tags, {
    #     Name        = "vectara-ng-inferentia-workbench"
    #     Description = "Inferentia node for Boomerang vectorization"
    #   })
    # }

    # NVMe Storage Nodes for Vector DB
    # UNCOMMENT when ready to deploy
    # nvme = {
    #   name = "vectara-ng-nvme-workbench"
    #
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 2
    #
    #   instance_types = ["i3en.xlarge"]
    #   capacity_type  = "ON_DEMAND"
    #   disk_size      = 100
    #   ami_type       = "AL2_x86_64"
    #   key_name       = local.ssh_key_name
    #
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type = "storage"
    #     node-group    = "nvme"
    #     storage-type  = "nvme"
    #   }
    #
    #   taints = {
    #     nvme = {
    #       key    = "storage-type"
    #       value  = "nvme"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    #
    #   tags = merge(local.ng_common_tags, {
    #     Name        = "vectara-ng-nvme-workbench"
    #     Description = "NVMe storage node for vector DB"
    #   })
    # }

    # High Memory Nodes for Vector DB Queries
    # UNCOMMENT when ready to deploy
    # highmem = {
    #   name = "vectara-ng-highmem-workbench"
    #
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 1
    #
    #   instance_types = ["r8i.xlarge"]
    #   capacity_type  = "ON_DEMAND"
    #   disk_size      = 100
    #   ami_type       = "AL2_x86_64"
    #   key_name       = local.ssh_key_name
    #
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type = "memory-optimized"
    #     node-group    = "highmem"
    #   }
    #
    #   taints = {
    #     highmem = {
    #       key    = "workload-type"
    #       value  = "memory-optimized"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    #
    #   tags = merge(local.ng_common_tags, {
    #     Name        = "vectara-ng-highmem-workbench"
    #     Description = "High memory node for vector DB queries"
    #   })
    # }
  }

  # EKS Add-ons - Essential for cluster functionality
  addons = {
    # CoreDNS - DNS resolution for services
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }

    # kube-proxy - Network proxy for services
    kube-proxy = {
      most_recent = true
    }

    # VPC CNI - Pod networking
    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        enableNetworkPolicy = "true" # Enable network policies
        env = {
          # Enable prefix delegation for more IPs per node
          ENABLE_PREFIX_DELEGATION = "true"
          # Warm pool configuration
          WARM_PREFIX_TARGET = "1"
        }
      })
    }

    # EKS Pod Identity Agent - Modern way to assign IAM roles to pods
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # Cluster-wide tags
  tags = {
    AppID       = "AR5852-QC003"
    BUSub       = "Data Analytics"
    Description = "Vectara Platform EKS Cluster"
    Lifecycle   = "QC"
    Name        = local.cluster_name
    Project     = "Vectara Platform Deployment"
  }

  # Node security group tags
  node_security_group_tags = {
    Name                                          = "vectara-eks-workbench-node-sg"
    "karpenter.sh/discovery"                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
}

################################################################################
# Outputs
################################################################################

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks_workbench.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks_workbench.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks_workbench.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks_workbench.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_workbench.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks_workbench.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks_workbench.node_security_group_id
}
