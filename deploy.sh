#!/bin/bash

set -e

function usage {
  echo "Usage: $0 [all|azure|images|cert-manager|oasis|models|monitoring]"
  echo
  echo "  all            Runs deploys of azure, images, cert-manager, oasis and summary"
  echo "  azure          Deploys Azure resources by bicep templates"
  echo "  images         Builds and push server/worker images to ACR"
  echo "  cert-manager   Installs cert-manager"
  echo "  oasis          Installs Oasis"
  echo "  summary        Prints a summary of azure resource names and URLs"
  echo
  echo "  setup          Runs piwind-model-files, models and analyses"
  echo "  piwind-model-files Upload PiWind key/model data to Azure Files share for models"
  echo "  models         Install/update models"
  echo "  analyses       Runs a setup script in OasisPlatform to create one portfolio and a set of analyses"
  echo
  echo "  update-kubectl Update kubectl context cluster"
  echo "  api [ls|run <id>] Basic API commands"
  echo ""
  exit 1
}

function setup {
  echo
  echo "Read README.md and set all required settings."
  echo
  echo "Overrider the default setting.sh file with OE_SETTINGS_FILE variable."
  exit 1
}

SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
DEPLOY_TYPE="$1"

# Settings file - use env var OE_SETTINGS_FILE to override
DEFAULT_SETTINGS_FILE="${SCRIPT_DIR}/settings/settings.sh"
source "${OE_SETTINGS_FILE:-$DEFAULT_SETTINGS_FILE}"

CERT_MANAGER_NAMESPACE="cert-manager"
CERT_MANAGER_CHART_VERSION="v1.7.0"
HELM_MODELS_NAME="models"
HELM_PLATFORM_NAME="platform"
HELM_MONITORING_NAME="monitoring"
AKS="oasis-enterprise-aks"
DOMAIN=${DNS_LABEL_NAME}.${LOCATION}.cloudapp.azure.com
ACR_NAME="acr${DNS_LABEL_NAME//[^a-z0-9]/}"             # Must be unique within Azure and alpha numeric only.
OASIS_API_URL="https://${DOMAIN}/api"
if [ -z "$AZURE_PARAM_FILE" ]; then
  AZURE_PARAM_FILE="${SCRIPT_DIR}/settings/azure/parameters.json"
fi
KEY_VAULT_NAME="$(grep -A1 '"keyVaultName":' "$AZURE_PARAM_FILE" | tail -n 1 | sed 's/.*"\([^"]*\)".*$/\1/g')"

export OASIS_API_URL

for evname in LOCATION DNS_LABEL_NAME RESOURCE_GROUP OASIS_PLATFORM_DIR OASIS_PIWIND_DIR LETSENCRYPT_EMAIL; do
  if [ -z "${!evname}" ]; then
    echo "Missing required environment variable: $evname"
    setup
  fi
done

if [ ! -f "$AZURE_PARAM_FILE" ]; then
  echo "Azure parameters file not found: $AZURE_PARAM_FILE"
  setup
fi

if [ ! -d "$OASIS_PLATFORM_DIR" ]; then
  echo "Oasis platform directory not found: $OASIS_PLATFORM_DIR"
  setup
fi

if [ ! -d "$OASIS_PIWIND_DIR" ]; then
  echo "Oasis PiWind directory not found: $OASIS_PIWIND_DIR"
  setup
fi

for chart in oasis-platform oasis-models oasis-monitoring; do
  CHART_DIR="${OASIS_PLATFORM_DIR}/kubernetes/charts/$chart/"
  if [ ! -d "$CHART_DIR" ]; then
    echo "Chart not found in OasisPlatform repository: $CHART_DIR"
    setup
  fi
done

if [[ ! "$DNS_LABEL_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "Invalid DNS_LABEL_NAME: $DNS_LABEL_NAME"
  setup
fi

if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Invalid email: $LETSENCRYPT_EMAIL"
  setup
fi

if [ -z "$KEY_VAULT_NAME" ]; then
  echo "No keyVaultName found in $AZURE_PARAM_FILE"
  setup
fi

# Make sure we are logged in
az login

function updateKubectlCluster() {
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS" --overwrite-existing
}

function helm_deploy() {

  HELM_OP=""
  if ! helm status "$3" &> /dev/null; then
    HELM_OP=install
  else
    HELM_OP=upgrade
  fi

  echo "Monitoring chart ${HELM_OP}..."

  ACR=$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query "loginServer" -o tsv)
  cat "$1" | \
    sed "s/\${ACR}/${ACR}/g" | \
    sed "s/\${DNS_LABEL_NAME}/${DNS_LABEL_NAME}/g" | \
    sed "s/\${LOCATION}/${LOCATION}/g" | \
    sed "s/\${DOMAIN}/${DOMAIN}/g" | \
    sed "s/\${LETSENCRYPT_EMAIL}/${LETSENCRYPT_EMAIL}/g" | \
    helm $HELM_OP "$3" "$2" -f- "${@:4}"

}


case "$DEPLOY_TYPE" in
  "azure")
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags oasis-enterprise=True

    # Deploy our resources
    az deployment group create \
     --name "${RESOURCE_GROUP}-deployment" \
     --resource-group "$RESOURCE_GROUP" \
     --template-file "${SCRIPT_DIR}/azure/bicep/main.bicep" \
     --parameters "@${AZURE_PARAM_FILE}" \
     --parameter "registryName=${ACR_NAME}" \
     --verbose
  ;;
  "images")

    # Build and push images

    ACR=$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query "loginServer" -o tsv)

    if [ -z "$ACR" ]; then
      echo "No ACR found"
      exit 1
    else
      echo "Container registry: $ACR"

      az acr login --name $ACR
    fi

    pushd "${OASIS_PLATFORM_DIR}/"

    if [ "$TRUST_PIP_HOSTS" == "1" ]; then
      cat Dockerfile.api_server | sed 's/pip install/pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' | \
        docker build -f - -t "${ACR}/coreoasis/api_server:dev" .
    else
      docker build -f Dockerfile.api_server -t "${ACR}/coreoasis/api_server:dev" .
    fi
    docker push "${ACR}/coreoasis/api_server:dev"

    if [ "$TRUST_PIP_HOSTS" == "1" ]; then
      cat Dockerfile.model_worker | sed 's/pip3 install/pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' | \
        docker build -f - -t "${ACR}/coreoasis/model_worker:dev" .
    else
      docker build -f Dockerfile.model_worker -t "${ACR}/coreoasis/model_worker:dev" .
    fi
    docker push "${ACR}/coreoasis/model_worker:dev"

    pushd "${OASIS_PLATFORM_DIR}/kubernetes/worker-controller"
    docker build -t "${ACR}/coreoasis/worker_controller:dev" \
     --build-arg PIP_TRUSTED_HOSTS="pypi.org files.pythonhosted.org" .
    docker push "${ACR}/coreoasis/worker_controller:dev"
  ;;
  "cert-manager")

    updateKubectlCluster

    # Check if cert-managers custom resource definitions exists

    if ! kubectl get crd -l app=cert-manager -l app.kubernetes.io/version=${CERT_MANAGER_CHART_VERSION} \
      2> /dev/null | grep -q certificaterequests.cert-manager.io; then

      echo "Applying cert-managers custom resource definitions..."
      kubectl apply -f ${SCRIPT_DIR}/helm/resources/cert-manager-${CERT_MANAGER_CHART_VERSION}.crds.yaml
    fi

    HELM_OP=""
    if ! helm status -n $CERT_MANAGER_NAMESPACE cert-manager &> /dev/null; then

      echo "Adding helm repository jetstack"
      helm repo add jetstack https://charts.jetstack.io
      helm repo update

      HELM_OP=install
    else

      HELM_OP=upgrade
    fi

    echo "Cert manager chart ${HELM_OP}..."

    helm $HELM_OP \
      cert-manager jetstack/cert-manager \
      --namespace $CERT_MANAGER_NAMESPACE \
      --create-namespace \
      --version $CERT_MANAGER_CHART_VERSION \
      -f settings/helm/cert-manager-values.yaml
  ;;
  "oasis")

    OASIS_FS_ACCOUNT_NAME="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-name --query "value" -o tsv)"
    OASIS_FS_ACCOUNT_KEY="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-key --query "value" -o tsv)"

    if [[ -z "$OASIS_FS_ACCOUNT_NAME" ]] || [[ -z "$OASIS_FS_ACCOUNT_KEY" ]]; then
      echo "Could not retrieve account name/key for file share"
      exit 1
    fi

    echo "got them "$OASIS_FS_ACCOUNT_NAME - $OASIS_FS_ACCOUNT_KEY

    updateKubectlCluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/platform-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-platform/" "$HELM_PLATFORM_NAME" \
      --set "azure.storageAccounts.oasisfs.accountName=${OASIS_FS_ACCOUNT_NAME}" --set "azure.storageAccounts.oasisfs.accountKey=${OASIS_FS_ACCOUNT_KEY}"
    echo "Environment: https://${DOMAIN}"
  ;;
  "all")
    $0 azure
    $0 images
    $0 cert-manager
    $0 oasis
    $0 summary
  ;;
  "summary")

    ACR=$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query "loginServer" -o tsv)
    echo "Azure:"
    echo " Location:       $LOCATION"
    echo " Resource group: $RESOURCE_GROUP"
    echo " AKS:            $AKS"
    echo " ACR:            $ACR"
    echo
    echo "Environment:"
    echo " Front:          https://${DOMAIN}"
    echo " API:            https://${DOMAIN}/api/"
    echo " Prometheus:     https://${DOMAIN}/prometheus/"
    echo " Grafana:        https://${DOMAIN}/grafana/"
    echo " Alert-manager:  https://${DOMAIN}/alert-manager/"
    echo " Keycloak:       https://${DOMAIN}/auth/admin/master/console/"
    echo
    echo "Update kubectl:"
    echo " $ az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS"
  ;;
  "update-kubectl"|"update-kc")
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "oasis-enterprise-aks" --overwrite-existing
  ;;
  "models")
    updateKubectlCluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/platform-values.yaml ${SCRIPT_DIR}/settings/helm/models-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-models/" "$HELM_MODELS_NAME"

    # Make sure the model is available before create analyses for it
        echo -n "Waiting for model to be registered: "
        while ! $0 api ls model | grep -qi oasislmf-piwind-1; do
          echo -n "."
          sleep 1
        done
        echo "OK"
  ;;
  "monitoring")
    updateKubectlCluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/monitoring-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-monitoring/" "$HELM_MONITORING_NAME"
  ;;
  "piwind-model-files"|"piwind-model_files")

    MODEL_PATHS="meta-data/model_settings.json oasislmf.json model_data/ keys_data/ tests/"
    OPTIONAL_MODEL_FILES="meta-data/chunking_configuration.json meta-data/scaling_configuration.json"

    for file in $MODEL_PATHS; do
      file="${OASIS_PIWIND_DIR}/$file"
      if ! [ -f "$file" ] && ! [ -d "$file" ]; then
        echo "Missing expected file: $file"
        exit 1
      fi
      echo "Found file: $file"
    done

    for file in $OPTIONAL_MODEL_FILES; do
      file="${OASIS_PIWIND_DIR}/$file"
      if [ -f "$file" ] && ! [ -d "$file" ]; then
        echo "Found optional file: $file"
      fi
    done

    OASIS_FS_ACCOUNT_NAME="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-name --query "value" -o tsv)"
    OASIS_FS_ACCOUNT_KEY="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-key --query "value" -o tsv)"

    az storage directory create --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models -n "OasisLMF"
    az storage directory create --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models -n "OasisLMF/PiWind"
    az storage directory create --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models -n "OasisLMF/PiWind/1"

    for file in $MODEL_PATHS; do
      file=${OASIS_PIWIND_DIR}/$file
      echo $file
      if [ -f "$file" ]; then
        az storage file upload --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models \
          --source "$file" --path "OasisLMF/PiWind/1/$(basename $file)"
      elif [ -d "$file" ]; then
        az storage directory create --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models -n "OasisLMF/PiWind/1/$(basename $file)"
        az storage file upload-batch --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY -s "$file" -d "models/OasisLMF/PiWind/1/$(basename $file)" --max-connections 10
      fi
      echo -n .
    done

    for file in $OPTIONAL_MODEL_FILES; do
      file=${OASIS_PIWIND_DIR}/$file
      if [ -f "$file" ] && ! [ -d "$file" ]; then
        az storage file upload --account-name $OASIS_FS_ACCOUNT_NAME --account-key $OASIS_FS_ACCOUNT_KEY --share-name models \
                  --source "$file" --path "OasisLMF/PiWind/1/$(basename $file)"
      fi
      echo -n .
    done
  ;;
  "setup")
    $0 piwind-model-files
    $0 models
    $0 analyses
    ;;
  "analyses")

    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/setup_env.sh \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceAccOEDPiWind.csv" \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceLocOEDPiWind.csv"
  ;;
  "api")
    export OASIS_AUTH_API=0
    export KEYCLOAK_TOKEN_URL="https://${DOMAIN}/auth/realms/oasis/protocol/openid-connect/token"
    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/api.sh "${@:2}"
    ;;
  "test")
    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/api.sh run 1
  ;;
  *)
    usage
    exit 1
  ;;
esac
