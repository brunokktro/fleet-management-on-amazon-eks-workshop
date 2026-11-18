function argocd_kill_port_forward (){
	pkill -9 -f "kubectl --context $1 port-forward svc/argocd-server -n argocd $2:80"
}

function argocd_credentials (){
	argocd_kill_port_forward $1 $2
	kubectl config use-context $1 >/dev/null
    kubectl --context $1 port-forward svc/argocd-server -n argocd $2:80 >/dev/null 2>&1 &
    # wait for the port-forward to accept connections (up to 30 s; 3 s was too short right after a rollout)
    for _ in $(seq 1 30); do
        curl -s -o /dev/null "http://localhost:$2/" && break
        sleep 1
    done
	export ARGOCD_PWD=$(kubectl get secrets argocd-initial-admin-secret -n argocd --template='{{index .data.password | base64decode}}' --context $1)
    # Argo CD 3.5 speaks h2c on its plaintext port and kubectl port-forward resets that on loopback
    # (argoproj/argo-cd#28179): --grpc-web keeps the CLI on HTTP/1.1 and --skip-test-tls skips the raw dial.
    argocd login "localhost:$2" --plaintext --grpc-web --skip-test-tls --username admin --password $ARGOCD_PWD --name $1
	echo "ArgoCD Username: admin"
	echo "ArgoCD Password: $ARGOCD_PWD"
	echo "ArgoCD URL: $IDE_URL/proxy/$2"
}

# The hub Argo CD is an EKS Capability: no pods, no admin password, no port-forward and no API
# server for the argocd CLI to log in to (core mode needs a local repo-server, which the hub lacks).
# Hub Applications are read and synced with kubectl; the UI is the managed endpoint, signed in
# through IAM Identity Center as workshop-admin.
function argocd_hub_credentials (){
	export ARGOCD_HUB_URL=$(aws ssm --region $AWS_REGION get-parameter --name eks-fleet-workshop-gitops-argocd-server-url --query Parameter.Value --output text)
	echo "ArgoCD (hub, EKS Capability): no CLI login, read Applications with 'hub_apps'"
	echo "ArgoCD Username: workshop-admin (IAM Identity Center, LOG IN VIA SSO)"
	echo "ArgoCD URL: $ARGOCD_HUB_URL"
}
# hub_apps [name-filter] : sync and health of the hub Applications, the kubectl equivalent of 'argocd app list'
function hub_apps (){
	kubectl --context ${HUB_CONTEXT:-fleet-hub-cluster} get applications -n argocd \
	  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status | { [ -n "$1" ] && grep -E "NAME|$1" || cat; }
}
function argocd_staging_credentials (){
	argocd_credentials ${STAGING_CONTEXT:-fleet-staging-cluster} 8082
}
function argocd_prod_credentials (){
	argocd_credentials ${PROD_CONTEXT:-fleet-prod-cluster} 8083
}
# fleet-spoke-dev exists only after the kro EksCluster lab (module fleet lifecycle)
function argocd_dev_credentials (){
	fleet_dev_kubeconfig || return 1
	argocd_credentials ${DEV_CONTEXT:-fleet-dev-cluster} 8084
}




