################################################################################
# Argo CD as an EKS Capability on the hub
#
# Argo CD runs in the EKS control plane, not as pods on fleet-hub-cluster. It authenticates
# users through IAM Identity Center (no local admin user) and reaches every cluster by ARN with
# its capability role (terraform/common/iam.tf) through access entries.
#
# The capability itself is created with the AWS CLI because `aws_eks_capability` only exists in
# the Terraform AWS provider 6.x and the `terraform-aws-modules/eks` v20 module used here does
# not validate against that provider. Identity Center objects are native Terraform resources.
################################################################################

# Identity Center instance: the workshop stack creates an account instance before this runs
# (Workshop Studio events: the Kiro subscription stack). In your own account the script
# creates one when none exists. Both ids land in SSM so the labs can read them.
resource "null_resource" "idc_instance" {
  triggers = {
    prefix = local.context_prefix
    region = local.region
  }
  provisioner "local-exec" {
    # bash + abspath: the scripts arrive without an executable bit and terraform -chdir does
    # not change the working directory of the provisioner.
    command = "bash ${abspath(path.module)}/scripts/idc-instance.sh"
    environment = {
      AWS_REGION = local.region
      SSM_PREFIX = local.context_prefix
    }
  }
}

data "aws_ssm_parameter" "idc_instance_arn" {
  name       = "${local.context_prefix}-idc-instance-arn"
  depends_on = [null_resource.idc_instance]
}

data "aws_ssm_parameter" "idc_store_id" {
  name       = "${local.context_prefix}-idc-identity-store-id"
  depends_on = [null_resource.idc_instance]
}

# The Argo CD ADMIN role maps to this group; the participant signs in as its only member.
resource "aws_identitystore_group" "argocd_admins" {
  identity_store_id = data.aws_ssm_parameter.idc_store_id.value
  display_name      = "fleet-argocd-admins"
  description       = "Argo CD administrators of the EKS fleet hub"
}

resource "aws_identitystore_user" "workshop_admin" {
  identity_store_id = data.aws_ssm_parameter.idc_store_id.value
  user_name         = var.argocd_admin_user_name
  display_name      = "Workshop Admin"
  name {
    given_name  = "Workshop"
    family_name = "Admin"
  }
  emails {
    value   = "${var.argocd_admin_user_name}@example.com"
    primary = true
  }
}

resource "aws_identitystore_group_membership" "workshop_admin" {
  identity_store_id = data.aws_ssm_parameter.idc_store_id.value
  group_id          = aws_identitystore_group.argocd_admins.group_id
  member_id         = aws_identitystore_user.workshop_admin.user_id
}

resource "null_resource" "argocd_capability" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = local.region
    role_arn     = data.aws_ssm_parameter.argocd_hub_role.value
    idc_arn      = data.aws_ssm_parameter.idc_instance_arn.value
    group_id     = aws_identitystore_group.argocd_admins.group_id
    namespace    = local.argocd_namespace
    ssm_prefix   = local.context_prefix
    script       = "bash ${abspath(path.module)}/scripts/argocd-capability.sh"
  }
  provisioner "local-exec" {
    command = self.triggers.script
    environment = {
      AWS_REGION        = self.triggers.region
      CLUSTER_NAME      = self.triggers.cluster_name
      CAPABILITY_ROLE   = self.triggers.role_arn
      IDC_INSTANCE_ARN  = self.triggers.idc_arn
      IDC_ADMIN_GROUP   = self.triggers.group_id
      ARGOCD_NAMESPACE  = self.triggers.namespace
      SSM_PREFIX        = self.triggers.ssm_prefix
    }
  }
  provisioner "local-exec" {
    when    = destroy
    command = "${self.triggers.script} delete"
    environment = {
      AWS_REGION   = self.triggers.region
      CLUSTER_NAME = self.triggers.cluster_name
    }
  }
  depends_on = [module.eks, aws_identitystore_group_membership.workshop_admin]
}

# The capability creates its own access entry on the hub with the Argo CD access policies.
# Deploying the fleet bootstrap (ApplicationSets, cluster Secrets, namespaces) needs cluster-admin.
resource "aws_eks_access_policy_association" "argocd_capability" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_ssm_parameter.argocd_hub_role.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [null_resource.argocd_capability]
}

data "aws_ssm_parameter" "argocd_server_url" {
  name       = "${local.context_prefix}-argocd-server-url"
  depends_on = [null_resource.argocd_capability]
}
