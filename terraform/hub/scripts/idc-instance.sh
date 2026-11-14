#!/usr/bin/env bash
# Finds (or creates) the IAM Identity Center instance of this account and records its ARN and
# identity store id in SSM as ${SSM_PREFIX}-idc-instance-arn / -idc-identity-store-id.
# In Workshop Studio events the instance already exists (created by the team stack before the
# hub); sso:CreateInstance is denied to participant-controlled roles there, so creation is only
# reached in a self-paced account.
set -euo pipefail
: "${AWS_REGION:?}" "${SSM_PREFIX:?}"

read_instance() {
  aws sso-admin list-instances --region "$AWS_REGION" --no-paginate \
    --query 'Instances[0].[InstanceArn,IdentityStoreId]' --output text 2>/dev/null || true
}

read -r ARN STORE <<<"$(read_instance)"
if [ -z "${ARN:-}" ] || [ "$ARN" = "None" ]; then
  echo "no Identity Center instance in this account, creating one"
  aws sso-admin create-instance --region "$AWS_REGION" --name "${SSM_PREFIX}-idc" >/dev/null
  for _ in $(seq 1 30); do
    read -r ARN STORE <<<"$(read_instance)"
    [ -n "${ARN:-}" ] && [ "$ARN" != "None" ] && break
    sleep 10
  done
fi
[ -n "${ARN:-}" ] && [ "$ARN" != "None" ] || { echo "Identity Center instance not available"; exit 1; }

aws ssm put-parameter --region "$AWS_REGION" --name "${SSM_PREFIX}-idc-instance-arn" --type String --value "$ARN" --overwrite >/dev/null
aws ssm put-parameter --region "$AWS_REGION" --name "${SSM_PREFIX}-idc-identity-store-id" --type String --value "$STORE" --overwrite >/dev/null
echo "Identity Center instance: $ARN (store $STORE)"
