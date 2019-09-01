GCE_PROJECT =
CLUSTER_NAME =

doctor: ## check the status of tools in your machine
	@make doctor-impl
doctor-impl: |check-kubectl check-gcloud auth-k8s-gcloud auth

check-kubectl:
ifeq (, $(shell which kubectl))
	$(error "No kubectl on PATH, install using ${GREEN}brew install kubectl${RESET}")
endif

check-gcloud:
ifeq (, $(shell which gcloud))
	$(error "gcloud was not found on PATH, install using ${GREEN}brew install gcloud${RESET}")
endif

auth: ## authenticate with google cloud
	gcloud auth configure-docker

auth-k8s-gcloud:
	gcloud config set project ${GCE_PROJECT}
	gcloud container clusters get-credentials $(CLUSTER_NAME) --zone us-central1-a

nginx:
	kubectl create ns nginx
	helm install stable/nginx-ingress --name nginx --namespace nginx
	kubectl --namespace nginx get services -o wide -w nginx-nginx-ingress-controller


define CLUSTER_ISSUER
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: mishu.drk@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: example-issuer-account-key
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          class: nginx
endef
export CLUSTER_ISSUER

issuer:
	echo "$$CLUSTER_ISSUER" > issuer.yaml
	kubectl apply -f issuer.yaml
	kubectl describe clusterissuer letsencrypt

cert-manager:
	kubectl create namespace cert-manager
	kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
	kubectl create clusterrolebinding cluster-admin-binding \
	  --clusterrole=cluster-admin \
	  --user=$(shell gcloud config get-value core/account)
	kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v0.8.1/cert-manager.yaml
