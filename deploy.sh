#!/bin/bash

set -e

function usage {
  echo "Usage: $0 [resource-group|base|azure|images|cert-manager|oasis|summary|piwind|piwindmodel-files|analyses|models|monitoring]"
  echo
  echo "  resource-group Create the resource group in Azure to be used for the Oasis platform"
  echo
  echo "  base           Deploys the platform by running azure, images, cert-manager, oasis, monitoring and summary"
  echo "  azure          Deploys Azure resources by bicep templates"
  echo "  images         Builds and push server/worker images from OasisPlatform to ACR"
  echo "  cert-manager   Installs cert-manager"
  echo "  oasis          Installs Oasis"
  echo "  monitoring     Installs Prometheus, alert manager and Grafana"
  echo "  summary        Prints a summary of azure resource names and URLs"
  echo
  echo "  piwind         Deploys PiWind and creates test analyses by running piwind-model-files, models and analyses"
  echo "  piwind-model-files Upload PiWind key/model data to Azure Files share for models"
  echo "  analyses       Runs a setup script in OasisPlatform to create one portfolio and a set of analyses"
  echo
  echo "  models         Install/update models defined in settings/helm/models-values.yaml"
  echo
  echo "  update-kubectl Update kubectl context cluster"
  echo "  api [ls|run <id>] Basic Oasis API commands"
  echo "  purge-env      Remove resource groups and purge key vaults"
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

function get_bicep_parameter {
  VALUE="$(grep -A1 "\"${1}\":" "$AZURE_PARAM_FILE" | tail -n 1 | sed 's/.*"\([^"]*\)".*$/\1/g')"
  if [ -z "$VALUE" ]; then
    echo "Parameter '${1} not found in $AZURE_PARAM_FILE" 1>&2
    exit 1
  fi
  echo "$VALUE"
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
DOMAIN=${DNS_LABEL_NAME}.${LOCATION}.cloudapp.azure.com
ACR_NAME="acr${DNS_LABEL_NAME//[^a-z0-9]/}"             # Must be unique within Azure and alpha numeric only.
OASIS_API_URL="https://${DOMAIN}/api"
if [ -z "$AZURE_PARAM_FILE" ]; then
  AZURE_PARAM_FILE="${SCRIPT_DIR}/settings/azure/parameters.json"
fi
KEY_VAULT_NAME="$(get_bicep_parameter "keyVaultName")"
CLUSTER_NAME="$(get_bicep_parameter "clusterName")"
AKS="${CLUSTER_NAME}-aks"
AKS_RESOURCE_GROUP="${RESOURCE_GROUP}-aks"
PORT_FORWARDING_LOCAL_PORT=8009

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
function az_login() {

  if ! az account list-locations &> /dev/null; then
    echo "Logging in..."
    az login
  fi
}

function updateKubectlCluster() {

  echo "Updating kubectl cluster"

  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing --only-show-errors
}


function helm_deploy() {

  HELM_OP=""
  if ! helm status "$3" &> /dev/null; then
    HELM_OP=install
  else
    HELM_OP=upgrade
  fi

  echo "Helm chart ${HELM_OP}..."

  ACR=$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query "loginServer" -o tsv)
  echo "Found ACR: $ACR"
  cat $1 | \
    sed "s/\${ACR}/${ACR}/g" | \
    sed "s/\${DNS_LABEL_NAME}/${DNS_LABEL_NAME}/g" | \
    sed "s/\${LOCATION}/${LOCATION}/g" | \
    sed "s/\${DOMAIN}/${DOMAIN}/g" | \
    sed "s/\${LETSENCRYPT_EMAIL}/${LETSENCRYPT_EMAIL}/g" | \
    helm $HELM_OP "$3" "$2" -f- "${@:4}"

  echo "Helm finished"
}

function kill_processes {

  count=0
  while [ $count -lt 3 ]; do
    for pid in $@; do
      if ps -p $pid &> /dev/null; then
        kill $pid
      fi
    done
    count=$(($count + 1))
  done

  for pid in $@; do
    if ps -p $pid &> /dev/null; then
      kill -9 $pid
    fi
  done
}


function stop_port_forward() {

  kill_processes $PORT_FORWARD_PID
  PORT_FORWARD_PID=""
}

function start_port_forward() {

  kubectl port-forward deploy/oasis-server ${PORT_FORWARDING_LOCAL_PORT}:8000 > /dev/null &
  PORT_FORWARD_PID=$!

  echo "Port forward started with pid $PORT_FORWARD_PID"

  while ! netstat -lpnt 2>&1 | grep "$PORT_FORWARD_PID" | grep -q ${PORT_FORWARDING_LOCAL_PORT}; do
    echo -n .
    sleep 1
  done
  echo "up"

  export OASIS_AUTH_API=1
  export KEYCLOAK_TOKEN_URL="http://localhost:43699/auth/realms/oasis/protocol/openid-connect/token"
  export OASIS_API_URL="http://localhost:$PORT_FORWARDING_LOCAL_PORT"
}

function cleanup() {

  stop_port_forward
}

trap cleanup EXIT SIGINT

az_login

case "$DEPLOY_TYPE" in
  "base")
    $0 azure
    $0 images
    $0 cert-manager
    $0 oasis
    $0 monitoring
    $0 summary
  ;;
  "custom")
#    $0 models
#    $0 analyses
  ;;
  "piwind")
    $0 piwind-model-files
    $0 models
    $0 analyses
  ;;
  "resource-group"|"resource-groups")
    echo "Creating resource group: $RESOURCE_GROUP"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags oasis-enterprise=True
  ;;
  "azure")

    echo "Deploying Azure resources..."

    if [ "$(az account show --query 'user.type' -o tsv)" == "servicePrincipal" ]; then
      CURRENT_USER_OBJECT_ID="$(az ad sp show --id "${servicePrincipalId}" --query 'objectId' -o tsv)"
    else
      CURRENT_USER_ID="$(az account show --query 'user.name' -o tsv)"
      CURRENT_USER_OBJECT_ID="$(az ad user show --id "$CURRENT_USER_ID" --query objectId -o tsv)"
    fi
    echo "Current user object id: $CURRENT_USER_OBJECT_ID"

    # Deploy our resources
    az deployment group create \
     --name "${RESOURCE_GROUP}-deployment" \
     --resource-group "$RESOURCE_GROUP" \
     --template-file "${SCRIPT_DIR}/azure/bicep/main.bicep" \
     --parameters "@${AZURE_PARAM_FILE}" \
     --parameter "registryName=${ACR_NAME}" \
     --parameter "nodeResourceGroup=${AKS_RESOURCE_GROUP}" \
     --parameter "currentUserObjectId=${CURRENT_USER_OBJECT_ID}" \
     --verbose
  ;;
  "images")

    echo "Deploying OasisPlatform images..."

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

    # Docker COPY issue https://github.com/moby/moby/issues/37965 - adds RUN true between COPY
    if [ "$TRUST_PIP_HOSTS" == "1" ]; then
      sed 's/pip install/pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' < Dockerfile.api_server | \
        sed 's/^COPY/RUN true\nCOPY/g' | \
        docker build -f - -t "${ACR}/coreoasis/api_server:dev" .
    else
      sed 's/^COPY/RUN true\nCOPY/g' < Dockerfile.api_server | \
          docker build -f - -t "${ACR}/coreoasis/api_server:dev" .
    fi
    docker push "${ACR}/coreoasis/api_server:dev"

    if [ "$TRUST_PIP_HOSTS" == "1" ]; then
      sed 's/pip3 install/pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' < Dockerfile.model_worker | \
        sed 's/^COPY/RUN true\nCOPY/g' | \
        sed 's/^FROM ubuntu:20.10/FROM ubuntu:20.04/g' | \
        docker build -f - -t "${ACR}/coreoasis/model_worker:dev" .
    else
       sed 's/^COPY/RUN true\nCOPY/g' < Dockerfile.model_worker | \
          sed 's/^FROM ubuntu:20.10/FROM ubuntu:20.04/g' | \
          docker build -f - -t "${ACR}/coreoasis/model_worker:dev" .
    fi
    docker push "${ACR}/coreoasis/model_worker:dev"

    pushd "${OASIS_PLATFORM_DIR}/kubernetes/worker-controller"
    docker build -t "${ACR}/coreoasis/worker_controller:dev" \
     --build-arg PIP_TRUSTED_HOSTS="pypi.org files.pythonhosted.org" .
    docker push "${ACR}/coreoasis/worker_controller:dev"
  ;;
  "cert-manager")

    echo "Deploying cert-manager..."

    updateKubectlCluster

    # Check if cert-managers custom resource definitions exists

    if ! kubectl get crd -l app=cert-manager -l app.kubernetes.io/version=${CERT_MANAGER_CHART_VERSION} \
      2> /dev/null | grep -q certificaterequests.cert-manager.io; then

      echo "Applying cert-managers custom resource definitions..."
      kubectl apply -f ${SCRIPT_DIR}/cert-manager/crd-dependency/cert-manager-${CERT_MANAGER_CHART_VERSION}.crds.yaml
    fi

    HELM_OP=""
    if ! helm status -n $CERT_MANAGER_NAMESPACE cert-manager &> /dev/null; then

      HELM_OP=install
    else

      HELM_OP=upgrade
    fi

    if [ "$HELM_OP" == "install" ] || [ "$TF_BUILD" == "True" ]; then
      echo "Adding helm repository jetstack"
      helm repo add jetstack https://charts.jetstack.io
      helm repo update
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

    echo "Deploying oasis..."

    echo "Retrieving oasis storage account name and keys"

    OASIS_FS_ACCOUNT_NAME="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-name --query "value" -o tsv)"
    OASIS_FS_ACCOUNT_KEY="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-key --query "value" -o tsv)"

    if [[ -z "$OASIS_FS_ACCOUNT_NAME" ]] || [[ -z "$OASIS_FS_ACCOUNT_KEY" ]]; then
      echo "Could not retrieve account name/key for file share"
      exit 1
    fi

    updateKubectlCluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/platform-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-platform/" "$HELM_PLATFORM_NAME" \
      --set "azure.storageAccounts.oasisfs.accountName=${OASIS_FS_ACCOUNT_NAME}" --set "azure.storageAccounts.oasisfs.accountKey=${OASIS_FS_ACCOUNT_KEY}"
    echo "Environment: https://${DOMAIN}"
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
    echo " $ az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
    echo
    echo "Docker login:"
    echo " $ az acr login --name $ACR"
  ;;
  "update-kubectl"|"update-kc")
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
  ;;
  "models")

    echo "Deploying models..."

    updateKubectlCluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/platform-values.yaml ${SCRIPT_DIR}/settings/helm/models-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-models/" "$HELM_MODELS_NAME"

    echo "Waiting for models to be registered: "
    MODELS=$(grep modelId "${SCRIPT_DIR}/settings/helm/models-values.yaml" | sed 's/^[- \t]*modelId:[ ]*\([^ #]*\).*/\1/')

    for model in $MODELS; do
      echo -n "$model..."
      while ! $0 api ls model | grep -qi "$model"; do
        echo -n "."
        sleep 1
      done
      echo
    done

    echo "Models deployed"
  ;;
  "monitoring")

    echo "Deploying monitoring..."

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

    az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF"
    az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF/PiWind"
    az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF/PiWind/1"

    for file in $MODEL_PATHS; do
      file=${OASIS_PIWIND_DIR}/$file
      echo $file
      if [ -f "$file" ]; then
        az storage file upload --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models \
          --source "$file" --path "OasisLMF/PiWind/1/$(basename $file)"
      elif [ -d "$file" ]; then
        az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF/PiWind/1/$(basename $file)"

        PATTERN="*"
        BASENAME="$(basename $file)"
        if [ "$BASENAME" == "tests" ]; then
          PATTERN="*OEDPiWind*.csv"
        fi

        az storage file upload-batch --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key $OASIS_FS_ACCOUNT_KEY \
         -s "$file" -d "models/OasisLMF/PiWind/1/${BASENAME}" --pattern "$PATTERN"
      fi
    done

    for file in $OPTIONAL_MODEL_FILES; do
      file=${OASIS_PIWIND_DIR}/$file
      if [ -f "$file" ] && ! [ -d "$file" ]; then
        az storage file upload --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models \
                  --source "$file" --path "OasisLMF/PiWind/1/$(basename $file)"
      fi
    done
  ;;
  "analyses")

    updateKubectlCluster
    start_port_forward

    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/setup_env.sh \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceAccOEDPiWind.csv" \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceLocOEDPiWind.csv"

    stop_port_forward
  ;;
  "purge-env")

    echo "Delete resource group: $RESOURCE_GROUP"
    az group delete -yn "$RESOURCE_GROUP"

    echo "Purge key vault: $KEY_VAULT_NAME"
    az keyvault purge --name "$KEY_VAULT_NAME"
  ;;
  "api")
    updateKubectlCluster
    start_port_forward

    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/api.sh "${@:2}"

    stop_port_forward
    ;;
  "test")
    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/api.sh run 1
  ;;
  *)
    usage
    exit 1
  ;;
esac
