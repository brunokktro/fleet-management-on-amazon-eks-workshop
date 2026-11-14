#!/usr/bin/env bash
# Renders gitops/fleet/kro/adopt-prod.yaml with the role and subnets of the existing prod cluster.
# Usage: ./render-adopt-prod.sh > adopt-prod.rendered.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD=${SPOKE_PROD_CLUSTER:-fleet-spoke-prod}
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
export PROD_CLUSTER_ROLE_ARN=$(aws eks describe-cluster --name "$PROD" --query cluster.roleArn --output text)
read -r PROD_SUBNET_1 PROD_SUBNET_2 < <(aws eks describe-cluster --name "$PROD" \
  --query 'cluster.resourcesVpcConfig.subnetIds[0:2]' --output text)
export PROD_SUBNET_1 PROD_SUBNET_2

envsubst '$AWS_REGION $PROD_CLUSTER_ROLE_ARN $PROD_SUBNET_1 $PROD_SUBNET_2' < "$SCRIPT_DIR/adopt-prod.yaml"
