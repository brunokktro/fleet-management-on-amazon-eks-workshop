output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
  EOT
}

output "configure_argocd" {
  description = "Argo CD on the hub is an EKS Capability: sign in through IAM Identity Center, drive the CLI in core mode"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
    kubectl config set-context --current --namespace argocd
    argocd login --core
    echo "Argo CD URL: ${nonsensitive(data.aws_ssm_parameter.argocd_server_url.value)} (LOG IN VIA SSO, user ${var.argocd_admin_user_name})"
    EOT
}

output "access_argocd" {
  description = "ArgoCD Access"
  value       = "${nonsensitive(data.aws_ssm_parameter.argocd_server_url.value)} (LOG IN VIA SSO, Identity Center user ${var.argocd_admin_user_name})"
}
