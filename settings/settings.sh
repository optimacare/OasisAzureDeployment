# Azure location - Use "Name" from Azure CLI:
# az account list-locations -o table
LOCATION="northcentralus"

# DNS name - must be unique within Azure and only contain characters permitted in domain names.
# Deployment will be accessible at ${DNS_LABEL_NAME}.${LOCATION}.cloudapp.azure.com after deployment.
DNS_LABEL_NAME=""

# Email to use for letsencrypt certificates
LETSENCRYPT_EMAIL=""

# Name of the resource group to deploy to
RESOURCE_GROUP="oasis-enterprise"

# Image build settings - tell pip to trust certificates from pypi.org and files.pythonhosted.org,
# do no verify them. In case your want to build locally and are behind a corporate proxy.
#TRUST_PIP_HOSTS=1

# Set to override path to OasisLMF/OasisPlatform repository with either branch platform-2.0-azure-sprint-2 checked
# out or platform-2.0 (if previous is merged)
#OASIS_PLATFORM_DIR=~/git/OasisPlatform/

# Set to override path to OasisLMF/OasisPiWind repository
#OASIS_PIWIND_DIR=~/git/OasisPiWind/

# Override the standard azure parameter file
#AZURE_PARAM_FILE="${SCRIPT_DIR}/settings/azure/myparameters.json"

# Default way of accessing the API with deploy.sh is to tunnel the traffic through the Kubernetes cluster.
# Set this variable to "1" to instead access the API directly through the domain name.
#CONNECT_DIRECTLY=1
