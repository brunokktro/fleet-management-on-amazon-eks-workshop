function deploy_fleet_dashboard (){
    export TF_VAR_aws_default_region=$AWS_REGION
    export TF_VAR_eks_dashboard_qs_region=$AWS_REGION
    export TF_VAR_cluster_names='["'${HUB_CLUSTER_NAME:-fleet-hub-cluster}'", "'${SPOKE_CLUSTER_NAME_PREFIX:-fleet-spoke}-staging'", "'${SPOKE_CLUSTER_NAME_PREFIX:-fleet-spoke}-prod'"]'
    echo "Deploying EKS Fleet Dashboard... this can take couple of minutes..."
    terraform -chdir=$WORKSHOP_DIR/terraform/fleet-dashboard init >/dev/null
    if terraform -chdir=$WORKSHOP_DIR/terraform/fleet-dashboard apply -auto-approve >/dev/null; then
        echo "EKS Fleet Dashboard successfully deployed..."
    else
        echo "EKS Fleet Dashboard deployment FAILED: read the errors above and run deploy_fleet_dashboard again"
        return 1
    fi
}

function refresh_fleet_dashboard(){
    local job_name="eks-fleet-management-dashboard"
    local region="$AWS_REGION"

    # Trigger the AWS Glue job
    job_run_id=$(aws glue start-job-run --job-name "$job_name" --region "$region" --query 'JobRunId' --output text)

    if [ -z "$job_run_id" ]; then
        echo "Error: Failed to trigger AWS Glue job that refreshes Fleet dashboard."
        return 1
    fi

    echo "The AWS Glue job has been triggered successfully to refresh the Fleet dashboard. Please allow couple of minutes for the process to complete."
}