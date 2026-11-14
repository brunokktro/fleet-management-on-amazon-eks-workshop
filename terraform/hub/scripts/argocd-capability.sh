#!/usr/bin/env bash
# Creates the Argo CD EKS Capability on the hub (idempotent), waits until it is ACTIVE and records
# its server URL in SSM as ${SSM_PREFIX}-argocd-server-url. `argocd-capability.sh delete` removes
# it (RETAIN keeps the CRDs and the Argo CD objects in the cluster).
#
# Needs an AWS CLI with `aws eks create-capability` (v2, late 2025 or newer). Lives in a script
# rather than `aws_eks_capability` because that Terraform resource needs provider 6.x, which the
# EKS module pinned here does not validate against.
set -euo pipefail
: "${AWS_REGION:?}" "${CLUSTER_NAME:?}"
NAME=argocd

if [ "${1:-}" = "delete" ]; then
  if aws eks describe-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" >/dev/null 2>&1; then
    aws eks delete-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" >/dev/null
    for _ in $(seq 1 60); do
      aws eks describe-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" >/dev/null 2>&1 || break
      sleep 15
    done
  fi
  exit 0
fi

: "${CAPABILITY_ROLE:?}" "${IDC_INSTANCE_ARN:?}" "${IDC_ADMIN_GROUP:?}" "${SSM_PREFIX:?}"
NAMESPACE=${ARGOCD_NAMESPACE:-argocd}

status() {
  aws eks describe-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" \
    --query 'capability.status' --output text 2>/dev/null || echo MISSING
}

if [ "$(status)" = "MISSING" ]; then
  CONFIG=$(cat <<JSON
{"argoCd":{"namespace":"${NAMESPACE}",
  "awsIdc":{"idcInstanceArn":"${IDC_INSTANCE_ARN}","idcRegion":"${AWS_REGION}"},
  "rbacRoleMappings":[{"role":"ADMIN","identities":[{"id":"${IDC_ADMIN_GROUP}","type":"SSO_GROUP"}]}]}}
JSON
)
  # IAM makes a new role visible to other services only after a few seconds; retry that one error.
  for attempt in $(seq 1 10); do
    set +e
    OUT=$(aws eks create-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" \
      --capability-name "$NAME" --type ARGOCD --role-arn "$CAPABILITY_ROLE" \
      --delete-propagation-policy RETAIN --configuration "$CONFIG" \
      --tags Blueprint="$CLUSTER_NAME" 2>&1); rc=$?
    set -e
    [ $rc -eq 0 ] && break
    if echo "$OUT" | grep -qi "trust policy for the provided role is invalid"; then
      echo "role not yet visible to EKS, retrying ($attempt/10)"; sleep 15; continue
    fi
    echo "$OUT" | grep -qi "already exists" && break
    echo "$OUT"; exit $rc
  done
fi

for _ in $(seq 1 60); do
  S=$(status)
  echo "$(date +%H:%M:%S) argocd capability: $S"
  case "$S" in
    ACTIVE) break ;;
    CREATE_FAILED|DELETE_FAILED|UPDATE_FAILED)
      aws eks describe-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" --query 'capability.health' --output json
      exit 1 ;;
  esac
  sleep 20
done
[ "$(status)" = "ACTIVE" ] || { echo "argocd capability did not become ACTIVE"; exit 1; }

URL=$(aws eks describe-capability --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --capability-name "$NAME" \
  --query 'capability.configuration.argoCd.serverUrl' --output text)
aws ssm put-parameter --region "$AWS_REGION" --name "${SSM_PREFIX}-argocd-server-url" --type String --value "$URL" --overwrite >/dev/null
echo "Argo CD: $URL"
