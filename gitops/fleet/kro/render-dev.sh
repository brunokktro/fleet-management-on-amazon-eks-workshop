#!/usr/bin/env bash
# Renders gitops/fleet/kro/ekscluster-dev.yaml with the values of this account:
# the hub VPC and two of its private subnets, the hub Argo CD role, the caller's IAM role.
# Usage: ./render-dev.sh [k8s-version] > ekscluster-dev.rendered.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB=${HUB_CLUSTER_NAME:-fleet-hub-cluster}
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
export DEV_K8S_VERSION=${1:-1.34}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# arn:aws:sts::<acct>:assumed-role/<Role>/<session> -> arn:aws:iam::<acct>:role/<Role>
caller=$(aws sts get-caller-identity --query Arn --output text)
role_name=$(echo "$caller" | awk -F/ '{print $2}')
export PARTICIPANT_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"

export HUB_ARGOCD_ROLE_ARN=$(aws ssm get-parameter --name eks-fleet-workshop-gitops-argocd-central-role \
  --query Parameter.Value --output text)
export HUB_VPC_ID=$(aws eks describe-cluster --name "$HUB" --query cluster.resourcesVpcConfig.vpcId --output text)
read -r HUB_SUBNET_1 HUB_SUBNET_2 < <(aws eks describe-cluster --name "$HUB" \
  --query 'cluster.resourcesVpcConfig.subnetIds[0:2]' --output text)
export HUB_SUBNET_1 HUB_SUBNET_2

envsubst '$AWS_REGION $AWS_ACCOUNT_ID $DEV_K8S_VERSION $PARTICIPANT_ROLE_ARN $HUB_ARGOCD_ROLE_ARN $HUB_VPC_ID $HUB_SUBNET_1 $HUB_SUBNET_2' \
  < "$SCRIPT_DIR/ekscluster-dev.yaml"
