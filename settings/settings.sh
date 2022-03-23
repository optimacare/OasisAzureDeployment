# Azure location - Use "Name" from Azure CLI:
# az account list-locations -o table
LOCATION="northcentralus"

# DNS name - must be unique within Azure and only contain characters permitted in domain names.
# Deployment will be accessible at ${DNS_LABEL_NAME}.${LOCATION}.cloudapp.azure.com after deployment.
DNS_LABEL_NAME=""

# Email to use for letsencrypt certificates
LETSENCRYPT_EMAIL=""

# Local git clone of OasisLMF/OasisPlatform with either branch platform-2.0-azure-sprint-1 checked out
# or platform-2.0 (if previous is merged)
OASIS_PLATFORM_DIR=~/git/OasisPlatform/

# Local git clone of OasisLMF/OasisPiWind
OASIS_PIWIND_DIR=~/git/OasisPiWind/

# Name of the resource group to deploy to
RESOURCE_GROUP="oasis-enterprise"

# Image build settings - tell pip to trust certificates from pypi.org and files.pythonhosted.org,
# do no verify them. In case your want to build locally and are behind a corporate proxy.
TRUST_PIP_HOSTS=0

# Override the standard azure parameter file
#AZURE_PARAM_FILE="${SCRIPT_DIR}/settings/azure/myparameters.json"
