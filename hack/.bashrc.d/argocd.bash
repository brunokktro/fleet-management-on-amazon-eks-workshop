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
    argocd login "localhost:$2" --plaintext --username admin --password $ARGOCD_PWD --name $1
	echo "ArgoCD Username: admin"
	echo "ArgoCD Password: $ARGOCD_PWD"
	echo "ArgoCD URL: $IDE_URL/proxy/$2"
}

# The hub Argo CD is an EKS Capability: no pods, no admin password, no port-forward. The CLI
# works in core mode (straight against the Application objects on the hub) and the UI is the
# managed endpoint, signed in through IAM Identity Center as workshop-admin.
function argocd_hub_credentials (){
	kubectl config use-context ${HUB_CONTEXT:-fleet-hub-cluster} >/dev/null
	kubectl config set-context --current --namespace argocd >/dev/null
	argocd login --core >/dev/null
	export ARGOCD_HUB_URL=$(aws ssm --region $AWS_REGION get-parameter --name eks-fleet-workshop-gitops-argocd-server-url --query Parameter.Value --output text)
	echo "ArgoCD (hub, EKS Capability) CLI: core mode on context ${HUB_CONTEXT:-fleet-hub-cluster}"
	echo "ArgoCD Username: workshop-admin (IAM Identity Center, LOG IN VIA SSO)"
	echo "ArgoCD URL: $ARGOCD_HUB_URL"
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




