################################################################################
# EKS Cluster – vectara-eks-cluster-workbench
################################################################################

resource "aws_ec2_tag" "vectara_eks_cluster_workbench_subnet_tags" {
  for_each = {
    "subnet-044cd019aa6cad905" = "subnet-044cd019aa6cad905"
    "subnet-0cd682c50ebfa727a" = "subnet-0cd682c50ebfa727a"
  }

  resource_id = each.value
  key         = "kubernetes.io/cluster/vectara-eks-cluster-workbench"
  value       = "shareds"
}

resource "aws_eks_cluster" "vectara_eks_cluster_workbench" {
  name     = "vectara-eks-cluster-workbench"
  role_arn = "arn:aws:iam::813071872585:role/DaspVectaraEksWorkbench"
  version  = "1.32"

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = "arn:aws:kms:us-east-1:813071872585:key/87f1a840-88bd-4cea-ae83-47ea6c94b5ff"
    }
  }

  # kubernetes_network_config {
  #   ip_family         = "ipv4"
  #   service_ipv4_cidr = "172.20.0.0/16"
  # }

  upgrade_policy {
    support_type = "EXTENDED"
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids = [
      "sg-030810e99b2ffc1f0",
      "sg-0de83503181c59936",
    ]
    subnet_ids = [
      "subnet-044cd019aa6cad905",
      "subnet-0cd682c50ebfa727a",
    ]
  }

  tags = {
    AppID       = "AR5852-QC003"
    BUSub       = "Data Analytics"
    Description = "Vectara Platform EKS Cluster"
    Lifecycle   = "QC"
    Name        = "vectara-eks-cluster-workbench"
    Project     = "Vectara Platform Deployment"
  }
}

locals {
  ng_common_tags = {
    "Lifecycle" = "QC"
    "AppID"     = "AR5852-QC003"
    "Project"   = "Vectara Platform Deployment"
    "BUSub"     = "Data Analytics"
    "RunSchedule" = "Weekday8to6"
  }

  eks_cluster_name    = "vectara-eks-cluster-workbench"
  eks_node_role_arn   = "arn:aws:iam::813071872585:role/DaspVectaraEksNodeGroupWorkbench"
  eks_subnets         = ["subnet-0cd682c50ebfa727a", "subnet-044cd019aa6cad905"]
  eks_ssh_key         = "Vectara-App-QC"
  eks_ng_sg          = ["sg-0de83503181c59936"]
}

resource "aws_eks_node_group" "vectara_ng_general_workbench" {
  node_group_name = "vectara-ng-general-workbench"
  cluster_name    = local.eks_cluster_name
  node_role_arn   = local.eks_node_role_arn
  subnet_ids      = local.eks_subnets
  ami_type        = "AL2_x86_64"
  instance_types  = ["m8i.4xlarge"]
  disk_size       = "100"

  remote_access {
    ec2_ssh_key               = local.eks_ssh_key
    source_security_group_ids = local.eks_ng_sg
  }

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  tags = merge(local.ng_common_tags, {
    "Name"        = "vectara-ng-general-workbench"
    "Description" = "General purpose nodes for Vectara shared services"
  })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
}

# resource "aws_eks_node_group" "vectara_ng_gpu_fcs_workbench" {
#   node_group_name = "vectara-ng-gpu-fcs-workbench"
#   cluster_name    = local.eks_cluster_name
#   node_role_arn   = local.eks_node_role_arn
#   subnet_ids      = local.eks_subnets
#   ami_type        = "AL2_x86_64_GPU"
#   instance_types  = ["g7e.xlarge"]
#   disk_size       = "200"

#   remote_access {
#     ec2_ssh_key               = local.eks_ssh_key
#     source_security_group_ids = local.eks_ng_sg
#   }

#   scaling_config {
#     desired_size = 0
#     max_size     = 1
#     min_size     = 0
#   }

#   tags = merge(local.ng_common_tags, {
#     "Name"        = "vectara-ng-gpu-fcs-workbench"
#     "Description" = "GPU node for Factual Consistency Server"
#   })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
# }

# resource "aws_eks_node_group" "vectara_ng_gpu_ml_workbench" {
#   node_group_name = "vectara-ng-gpu-ml-workbench"
#   cluster_name    = local.eks_cluster_name
#   node_role_arn   = local.eks_node_role_arn
#   subnet_ids      = local.eks_subnets
#   ami_type        = "AL2_x86_64_GPU"
#   instance_types  = ["g6.xlarge"]
#   disk_size       = "200"

#   remote_access {
#     ec2_ssh_key               = local.eks_ssh_key
#     source_security_group_ids = local.eks_ng_sg
#   }

#   scaling_config {
#     desired_size = 1
#     max_size     = 2
#     min_size     = 1
#   }

#   tags = merge(local.ng_common_tags, {
#     "Name"        = "vectara-ng-gpu-ml-workbench"
#     "Description" = "GPU nodes for Reranker and Vectara LLM"
#   })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
# }

# resource "aws_eks_node_group" "vectara_ng_inferentia_workbench" {
#   node_group_name = "vectara-ng-inferentia-workbench"
#   cluster_name    = local.eks_cluster_name
#   node_role_arn   = local.eks_node_role_arn
#   subnet_ids      = local.eks_subnets
#   ami_type        = "AL2_x86_64"
#   instance_types  = ["inf2.xlarge"]
#   disk_size       = "100"

#   remote_access {
#     ec2_ssh_key               = local.eks_ssh_key
#     source_security_group_ids = local.eks_ng_sg
#   }

#   scaling_config {
#     desired_size = 1
#     max_size     = 1
#     min_size     = 1
#   }

#   tags = merge(local.ng_common_tags, {
#     "Name"        = "vectara-ng-inferentia-workbench"
#     "Description" = "Inferentia node for Boomerang vectorisation"
#   })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
# }

# resource "aws_eks_node_group" "vectara_ng_nvme_workbench" {
#   node_group_name = "vectara-ng-nvme-workbench"
#   cluster_name    = local.eks_cluster_name
#   node_role_arn   = local.eks_node_role_arn
#   subnet_ids      = local.eks_subnets
#   ami_type        = "AL2_x86_64"
#   instance_types  = ["i3en.xlarge"]
#   disk_size       = "100"

#   remote_access {
#     ec2_ssh_key               = local.eks_ssh_key
#     source_security_group_ids = local.eks_ng_sg
#   }

#   scaling_config {
#     desired_size = 1
#     max_size     = 2
#     min_size     = 1
#   }

#   tags = merge(local.ng_common_tags, {
#     "Name"        = "vectara-ng-nvme-workbench"
#     "Description" = "NVME storage node for vector DB"
#   })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
# }

# resource "aws_eks_node_group" "vectara_ng_highmem_workbench" {
#   node_group_name = "vectara-ng-highmem-workbench"
#   cluster_name    = local.eks_cluster_name
#   node_role_arn   = local.eks_node_role_arn
#   subnet_ids      = local.eks_subnets
#   ami_type        = "AL2_x86_64"
#   instance_types  = ["r8i.xlarge"]
#   disk_size       = "100"

#   remote_access {
#     ec2_ssh_key               = local.eks_ssh_key
#     source_security_group_ids = local.eks_ng_sg
#   }

#   scaling_config {
#     desired_size = 1
#     max_size     = 1
#     min_size     = 1
#   }

#   tags = merge(local.ng_common_tags, {
#     "Name"        = "vectara-ng-highmem-workbench"
#     "Description" = "High memory node for vector DB queries"
#   })

#   depends_on = [aws_eks_cluster.vectara_eks_cluster_workbench]
# }
