################################################################################
# ArgoCD EKS Access
################################################################################
# Argo CD on the hub runs as an EKS Capability (managed, outside the cluster). This is its
# capability role: EKS assumes it to reach AWS services for Argo CD, and the spokes grant it
# cluster-admin through an access entry (terraform/spokes/main.tf), which is how the managed
# Argo CD reaches other clusters. It replaced the Pod Identity role of the self-managed hub
# Argo CD; the SSM parameter below kept its name so every consumer reads the new ARN.
resource "aws_iam_role" "argocd_central" {
  name_prefix = "${local.context_prefix}-argocd-hub"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEksCapabilitiesToAssumeRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
      },
    ]
  })
  tags = local.tags
}
# Git repositories are reached with Kubernetes repository Secrets, so the capability needs
# no CodeConnections or Secrets Manager permissions. ECR pull covers OCI Helm charts.
resource "aws_iam_role_policy_attachment" "argocd_central_ecr" {
  role       = aws_iam_role.argocd_central.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
# Creating parameter for all clusters to read
resource "aws_ssm_parameter" "argocd_hub_role" {
  name  = "${local.context_prefix}-${var.ssm_parameter_name_argocd_role_suffix}"
  type  = "String"
  value = aws_iam_role.argocd_central.arn
}
################################################################################
# Team Roles Backend
################################################################################
resource "aws_iam_role" "backend_team_view" {
  name_prefix = "backend-team-view-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : data.aws_iam_session_context.current.issuer_arn
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = local.tags
}
# Creating parameter for all clusters to read
resource "aws_ssm_parameter" "backend_team_view_role" {
  name  = "${local.context_prefix}-${var.backend_team_view_role_suffix}"
  type  = "String"
  value = aws_iam_role.backend_team_view.arn
}
################################################################################
# Team Roles Frontend
################################################################################
resource "aws_iam_role" "frontend_team_view" {
  name_prefix = "frontend-team-view-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : data.aws_iam_session_context.current.issuer_arn
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = local.tags
}
# Creating parameter for all clusters to read
resource "aws_ssm_parameter" "frontend_team_view_role" {
  name  = "${local.context_prefix}-${var.frontend_team_view_role_suffix}"
  type  = "String"
  value = aws_iam_role.frontend_team_view.arn
}