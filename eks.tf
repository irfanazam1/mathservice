################################################################################
# EKS Cluster - vectara-eks-cluster-workbench
#
# Uses terraform-aws-modules/eks module (v21.3.1) with:
#   - API-mode authentication (modern)
#   - IRSA enabled
#   - Essential addons: coredns, kube-proxy, vpc-cni, eks-pod-identity-agent
#   - General node group active; GPU/Inferentia/NVMe/HighMem commented out
#
# BEFORE APPLYING:
#   1. Replace vpc_id = "vpc-XXXXX" with your actual VPC ID:
#      aws ec2 describe-subnets --subnet-ids subnet-044cd019aa6cad905 \
#        --query 'Subnets[0].VpcId' --output text
#   2. Ensure SSH key pair "Vectara-App-QC" exists in the target region
#   3. Verify security groups sg-030810e99b2ffc1f0 and sg-0de83503181c59936 exist
################################################################################

# terraform {
#   required_version = ">= 1.0"

#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 5.0"
#     }
#   }
# }

# provider "aws" {
#   region = "us-east-1" # Change if deploying to a different region
# }

################################################################################
# Locals
################################################################################

locals {
  cluster_name = "vectara-eks-cluster-workbench"

  # Common tags applied to all node groups
  ng_common_tags = {
    Lifecycle   = "QC"
    AppID       = "AR5852-QC003"
    Project     = "Vectara Platform Deployment"
    BUSub       = "Data Analytics"
    RunSchedule = "Weekday8to6"
  }

  # Subnets for cluster and node groups
  # These must be private subnets with NAT Gateway access (endpoint_public_access = false)
  subnet_ids = [
    "subnet-044cd019aa6cad905",
    "subnet-0cd682c50ebfa727a",
  ]

  # SSH key pair name for node access
  ssh_key_name = "Vectara-App-QC"
}

################################################################################
# Subnet Tags - Required for EKS load balancer discovery
################################################################################

resource "aws_ec2_tag" "vectara_eks_cluster_workbench_subnet_tags" {
  for_each = toset(local.subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "shared"
}

################################################################################
# EKS Cluster Module
################################################################################

module "eks_workbench" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.3.1"

  name               = local.cluster_name
  kubernetes_version = "1.32"

  # ---------------------------------------------------------------------------
  # VPC / Networking
  # ---------------------------------------------------------------------------
  # NOTE: Replace vpc-08650e45904b81df7 with your actual VPC ID before applying.
  # Retrieve it with:
  #   aws ec2 describe-subnets --subnet-ids subnet-044cd019aa6cad905 \
  #     --query 'Subnets[0].VpcId' --output text
  #
  # Subnet guidance:
  #   - Both subnets must be PRIVATE (NAT Gateway required for image pulls)
  #   - /24 CIDR minimum recommended per subnet (~250 IPs)
  #   - VPC CNI prefix delegation is enabled below for higher pod density
  #   - Add public subnets tagged kubernetes.io/role/elb=1 for internet-facing LBs
  vpc_id     = "vpc-08650e45904b81df7" # TODO: Replace with your actual VPC ID
  subnet_ids = local.subnet_ids

  # ---------------------------------------------------------------------------
  # API Endpoint
  # ---------------------------------------------------------------------------
  endpoint_private_access = true
  endpoint_public_access  = false

  # ---------------------------------------------------------------------------
  # Additional Security Groups (control plane access)
  # ---------------------------------------------------------------------------
  additional_security_group_ids = [
    "sg-030810e99b2ffc1f0",
    "sg-0de83503181c59936",
  ]

  # ---------------------------------------------------------------------------
  # Authentication
  # Modern API mode — access managed via access_entries, not aws-auth ConfigMap
  # ---------------------------------------------------------------------------
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # ---------------------------------------------------------------------------
  # IRSA — IAM Roles for Service Accounts
  # Allows pods to assume IAM roles (S3, Secrets Manager, ECR, etc.)
  # ---------------------------------------------------------------------------
  enable_irsa                     = true
  include_oidc_root_ca_thumbprint = false

  # ---------------------------------------------------------------------------
  # Managed Node Groups
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {

    # -------------------------------------------------------------------------
    # General Purpose Nodes — always active
    # -------------------------------------------------------------------------
    general = {
      name = "vectara-ng-general-workbench"

      iam_role_name            = "vectara-ng-general-wb"   
      iam_role_use_name_prefix = true                      

      desired_size = 2
      min_size     = 2
      max_size     = 4

      instance_types = ["m8i.4xlarge"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 100
      ami_type       = "AL2_x86_64"

      key_name               = local.ssh_key_name
      vpc_security_group_ids = ["sg-0de83503181c59936"]
      subnet_ids             = local.subnet_ids

      enable_cluster_autoscaler = true

      labels = {
        workload-type = "general"
        node-group    = "general"
      }

      tags = merge(local.ng_common_tags, {
        Name        = "vectara-ng-general-workbench"
        Description = "General purpose nodes for Vectara shared services"
      })
    }

    # -------------------------------------------------------------------------
    # GPU — Factual Consistency Server (FCS)
    # Uncomment when ready to deploy. Scales to zero when not needed.
    # -------------------------------------------------------------------------
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
    #
    #   key_name               = local.ssh_key_name
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type    = "gpu"
    #     node-group       = "gpu-fcs"
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

    # -------------------------------------------------------------------------
    # GPU — ML (Reranker and Vectara LLM)
    # Uncomment when ready to deploy.
    # -------------------------------------------------------------------------
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
    #
    #   key_name               = local.ssh_key_name
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type    = "gpu"
    #     node-group       = "gpu-ml"
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

    # -------------------------------------------------------------------------
    # Inferentia — Boomerang Vectorization
    # Uncomment when ready to deploy.
    # -------------------------------------------------------------------------
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
    #
    #   key_name               = local.ssh_key_name
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #
    #   enable_cluster_autoscaler = true
    #
    #   labels = {
    #     workload-type           = "inferentia"
    #     node-group              = "inferentia"
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

    # -------------------------------------------------------------------------
    # NVMe Storage — Vector DB
    # Uncomment when ready to deploy.
    # -------------------------------------------------------------------------
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
    #
    #   key_name               = local.ssh_key_name
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #
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

    # -------------------------------------------------------------------------
    # High Memory — Vector DB Queries
    # Uncomment when ready to deploy.
    # -------------------------------------------------------------------------
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
    #
    #   key_name               = local.ssh_key_name
    #   vpc_security_group_ids = ["sg-0de83503181c59936"]
    #   subnet_ids             = local.subnet_ids
    #
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

  } # end eks_managed_node_groups

  # ---------------------------------------------------------------------------
  # EKS Add-ons
  # ---------------------------------------------------------------------------
  addons = {

    # CoreDNS — in-cluster DNS resolution for services and pods
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }

    # kube-proxy — iptables/IPVS rules for Kubernetes Services
    kube-proxy = {
      most_recent = true
    }

    # VPC CNI — pod networking; prefix delegation for higher pod density
    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    # EKS Pod Identity Agent — modern IAM-role-per-pod (complements IRSA)
    eks-pod-identity-agent = {
      most_recent = true
    }

  } # end addons

  # ---------------------------------------------------------------------------
  # Cluster-wide tags
  # ---------------------------------------------------------------------------
  tags = {
    AppID       = "AR5852-QC003"
    BUSub       = "Data Analytics"
    Description = "Vectara Platform EKS Cluster"
    Lifecycle   = "QC"
    Name        = local.cluster_name
    Project     = "Vectara Platform Deployment"
  }

  # ---------------------------------------------------------------------------
  # Node security group extra tags
  # karpenter.sh/discovery enables Karpenter node auto-discovery if used later
  # ---------------------------------------------------------------------------
  node_security_group_tags = {
    Name                                          = "vectara-eks-workbench-node-sg"
    "karpenter.sh/discovery"                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }

} # end module "eks_workbench"

################################################################################
# Outputs
################################################################################

output "cluster_id" {
  description = "The ID/name of the EKS cluster"
  value       = module.eks_workbench.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS control plane API server"
  value       = module.eks_workbench.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster control plane"
  value       = module.eks_workbench.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN used by the EKS cluster"
  value       = module.eks_workbench.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for kubectl communication"
  value       = module.eks_workbench.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — used when creating IRSA IAM roles"
  value       = module.eks_workbench.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = module.eks_workbench.node_security_group_id
}

#╷
#│ Error: waiting for EKS Node Group (vectara-eks-cluster-workbench:vectara-ng-general-workbench-20260421135431092400000001) create: unexpected state 'CREATE_FAILED', wanted target 'ACTIVE'. last error: i-031acb4e8548c9512, i-084320a39cb8afc5f: NodeCreationFailure: Unhealthy nodes in the kubernetes cluster
#│
#│   with module.eks_workbench.module.eks_managed_node_group["general"].aws_eks_node_group.this[0],
#│   on .terraform/modules/eks_workbench/modules/eks-managed-node-group/main.tf line 447, in resource "aws_eks_node_group" "this":
#│  447: resource "aws_eks_node_group" "this" {
#│
#╵
 
