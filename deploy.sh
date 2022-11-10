#!/bin/bash

set -e

function usage {
  echo "Usage: $0 <command>"
  echo
  echo "Available commands:"
  echo "  resource-group Create the resource group in Azure to be used for the Oasis platform"
  echo
  echo "  base           Deploys the platform by running azure, db-init, images, cert-manager, oasis, monitoring and summary"
  echo "  azure          Deploys Azure resources by bicep templates"
  echo "  db-init        Initialize database users"
  echo "  images         Builds and push server/worker images from OasisPlatform to ACR"
  echo "  cert-manager   Installs cert-manager"
  echo "  oasis          Installs Oasis"
  echo "  monitoring     Installs Prometheus, alert manager and Grafana"
  echo "  summary        Prints a summary of azure resource names and URLs"
  echo
  echo "  piwind         Deploys PiWind and creates test analyses by running piwind-model-files, models and analyses"
  echo "  piwind-model-files"
  echo "                 Upload PiWind key/model data to Azure Files share for models"
  echo "  analyses       Runs a setup script in OasisPlatform to create one portfolio and a set of analyses"
  echo
  echo "  models         Install/update models defined in settings/helm/models-values.yaml"
  echo
  echo "  update-kubectl Update kubectl context cluster"
  echo "  api [ls|run <id>]"
  echo "                 Basic Oasis API commands"
  echo "  purge [group|resources|charts]"
  echo "                 Remove one of:"
  echo "                    group - resource group(s) (everything)"
  echo "                    resources - removes all resources in the group but keep the group"
  echo "                    charts - uninstall all Helm charts"
  echo "  get-acr        Shot ACR name."
  echo ""
  exit 0
}

function setup {
  echo
  echo "Read README.md and set all required settings."
  echo
  echo "Overrider the default setting.sh file with OE_SETTINGS_FILE variable."
  exit 1
}

function get_bicep_parameter {
  value="$(grep -A1 "\"${1}\":" "$AZURE_PARAM_FILE" | tail -n 1 | sed 's/.*"\([^"]*\)".*$/\1/g')"

  if [ -z "$value" ]; then
    echo "Parameter '${1} not found in $AZURE_PARAM_FILE" 1>&2
    exit 1
  fi

  echo "$value"
}

SCRIPT_DIR="$(cd $(dirname "$0"); pwd)"
UPLOAD_MODEL_DATA="${SCRIPT_DIR}/scripts/upload_model_data.sh"
deploy_type="$1"

# Settings file - use env var OE_SETTINGS_FILE to override
default_settings_file="${SCRIPT_DIR}/settings/settings.sh"
source "${OE_SETTINGS_FILE:-$default_settings_file}"

CERT_MANAGER_NAMESPACE="cert-manager"
CERT_MANAGER_CHART_VERSION="v1.7.0"
HELM_MODELS_NAME="models"
HELM_PLATFORM_NAME="platform"
HELM_MONITORING_NAME="monitoring"
PORT_FORWARDING_LOCAL_PORT=8009
if [ -z "$AZURE_PARAM_FILE" ]; then
  AZURE_PARAM_FILE="${SCRIPT_DIR}/settings/azure/parameters.json"
fi
OASIS_PLATFORM_DIR="${OASIS_PLATFORM_DIR:-$(cd ${SCRIPT_DIR}/../OasisPlatform; pwd)}"
OASIS_PIWIND_DIR="${OASIS_PIWIND_DIR:-$(cd ${SCRIPT_DIR}/../OasisPiWind; pwd)}"

domain=${DNS_LABEL_NAME}.${LOCATION}.cloudapp.azure.com
acr_name="acr${DNS_LABEL_NAME//[^a-z0-9]/}"             # Must be unique within Azure and alpha numeric only.
cluster_name="$(get_bicep_parameter "clusterName")"
aks="${cluster_name}-aks"
aks_resource_group="${RESOURCE_GROUP}-aks"
temporary_files=()

export OASIS_API_URL="https://${domain}/api"
export OASIS_AUTH_API=1

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

# Make sure we are logged in
function az_login() {

  if ! az account list-locations &> /dev/null; then
    echo "Logging in..."
    az login
  fi
}

function update_kubectl_cluster() {

  echo "Updating kubectl cluster"

  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$cluster_name" --overwrite-existing --only-show-errors
}

function helm_deploy() {

  helm_operation=""
  if ! helm status "$3" &> /dev/null; then
    helm_operation=install
  else
    helm_operation=upgrade
  fi

  acr=$(get_acr)

  echo "Helm chart ${helm_operation}..."

  inputs=""
  i=0
  temp_dir=$(mktemp -d)
  temporary_files+=("$temp_dir")
  for value_file in $1; do

    i=$((i + 1))
    file="${temp_dir}/$i"

    cat "$value_file" | \
        sed "s/\${ACR}/${acr}/g" | \
        sed "s/\${DNS_LABEL_NAME}/${DNS_LABEL_NAME}/g" | \
        sed "s/\${LOCATION}/${LOCATION}/g" | \
        sed "s/\${DOMAIN}/${domain}/g" | \
        sed "s/\${LETSENCRYPT_EMAIL}/${LETSENCRYPT_EMAIL}/g" \
        > "$file"

    inputs+=" -f $file"
  done

  helm $helm_operation $inputs "$3" "$2" "${@:4}"

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
    count=$((count + 1))
  done

  for pid in $@; do
    if ps -p $pid &> /dev/null; then
      kill -9 $pid
    fi
  done
}

function check_domain_access() {

  echo -n "Checking access to ${OASIS_API_URL}... "

  if response_code=$(curl -sk --connect-timeout 3 --write-out "%{http_code}" --output /dev/null "$OASIS_API_URL"); then
    [[ "$response_code" == "200" ]] || [[ "$response_code" == "301" ]] && echo "OK" && return 0
  fi

  echo "not OK - will use port forwarding"
  return 1
}

function stop_port_forward() {

  kill_processes $port_forward_pid
  port_forward_pid=""
}

function start_port_forward() {

  update_kubectl_cluster

  kubectl port-forward deploy/oasis-server ${PORT_FORWARDING_LOCAL_PORT}:8000 > /dev/null &
  port_forward_pid=$!

  echo "Port forward started with pid $port_forward_pid"

  while ! netstat -lpnt 2>&1 | grep "$port_forward_pid" | grep -q ${PORT_FORWARDING_LOCAL_PORT}; do
    echo -n .
    sleep 1
  done
  echo "up"

  export OASIS_API_URL="http://localhost:$PORT_FORWARDING_LOCAL_PORT"
}

function start_port_forward_if_needed() {

  if [ "$CONNECT_DIRECTLY" != "1" ]; then
    start_port_forward
  fi
}

function cleanup_temporary_files() {

  for file in "${temporary_files[@]}"; do
    if [ -f "$file" ]; then
      rm -f "$file"
    elif [ -d "$file" ]; then
      rm  $file/*
      rm -r "$file"
    fi
  done
}

function cleanup() {

  cleanup_temporary_files
  stop_port_forward
}

trap cleanup EXIT SIGINT

function get_secret {

  key_vault_name="$(get_key_vault_name)"

  value="$(az keyvault secret show --vault-name "$key_vault_name" --name "$1" --query "value" -o tsv)"

  if [ -z "$value" ]; then
    echo "No secret found by name $1" 1>&2
    exit 1
  fi

  echo $value
}

function get_or_generate_secret {

  key_vault_name="$(get_key_vault_name)"

  if ! az keyvault secret list --vault-name "$key_vault_name" --query "[].name" -o tsv | grep -q "$1"; then
    echo "Generating secret $1..." 1>&2

    az keyvault secret set --vault-name "$key_vault_name" --name "$1" --value "$(< /dev/urandom tr -dc '_A-Z-a-z-0-9#=?+-' | head -c32)" --query "value" -o tsv
  else
    az keyvault secret show --vault-name "$key_vault_name" --name "$1" --query "value" -o tsv
  fi
}

function get_key_vault_name {

  VALUE="$(az keyvault list -g "$RESOURCE_GROUP" --query '[?"tags.oasis-enterprise" == "True"].name' -o tsv | head -n 1)"

  if [ -z "$VALUE" ]; then
    echo "No key vault found" 1>&2
    exit 1
  fi

  echo $VALUE
}

function get_key_vault_tenant_id {

  key_vault_name="$(get_key_vault_name)"

  VALUE="$(az keyvault show --name "${key_vault_name}" --query 'properties.tenantId' -o tsv)"

  if [ -z "$VALUE" ]; then
    echo "No key vault tenant id found" 1>&2
    exit 1
  fi

  echo $VALUE
}

function get_aks_identity_client_id {

  VALUE="$(az aks list --resource-group "$RESOURCE_GROUP" --query "[?name == 'oasis-enterprise'].identityProfile.kubeletidentity.clientId" -o tsv)"

  if [ -z "$VALUE" ]; then
    echo "No aks identify client id found" 1>&2
    exit 1
  fi

  echo $VALUE
}

function get_acr {

  VALUE="$(az acr show -g "$RESOURCE_GROUP" -n "$acr_name" --query "loginServer" -o tsv)"
  if [ -z "$VALUE" ]; then
    echo "No ACR found" 1>&2
    exit 1
  fi

  echo $VALUE
}

az_login

case "$deploy_type" in
  "base")
    $0 azure
    $0 db-init
    $0 images
    $0 cert-manager
    $0 oasis
    $0 monitoring
    $0 summary
  ;;
  "custom")
  ;;
  "piwind")
    $0 piwind-model-files
    $0 models
    $0 analyses
  ;;
  "resource-group"|"resource-groups")
    echo "Creating resource group: $RESOURCE_GROUP"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags oasis-enterprise=True

    az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
    az extension add --name aks-preview
  ;;
  "azure")

    echo "Deploying Azure resources..."

    if [ "$(az account show --query 'user.type' -o tsv)" == "servicePrincipal" ]; then
      CURRENT_USER_OBJECT_ID="$(az ad sp show --id "${servicePrincipalId}" --query 'id' -o tsv)"
    else
      CURRENT_USER_ID="$(az account show --query 'user.name' -o tsv)"
      CURRENT_USER_OBJECT_ID="$(az ad user show --id "$CURRENT_USER_ID" --query id -o tsv)"
    fi
    echo "Current user object id: $CURRENT_USER_OBJECT_ID"

    # Deploy our resources
    az deployment group create \
     --name "${RESOURCE_GROUP}-deployment" \
     --resource-group "$RESOURCE_GROUP" \
     --template-file "${SCRIPT_DIR}/azure/bicep/main.bicep" \
     --parameters "@${AZURE_PARAM_FILE}" \
     --parameter "registryName=${acr_name}" \
     --parameter "nodeResourceGroup=${aks_resource_group}" \
     --parameter "currentUserObjectId=${CURRENT_USER_OBJECT_ID}" \
     --verbose
  ;;
  "db-init")

    echo "Generating user passwords..."
    oasis_db_password=$(get_or_generate_secret "oasis-db-password")
    keycloak_db_password=$(get_or_generate_secret "keycloak-db-password")
    celery_db_password=$(get_or_generate_secret "celery-db-password")

    echo "Get environment settings..."
    key_vault_name="$(get_key_vault_name)"
    key_vault_tenant_id="$(get_key_vault_tenant_id)"
    aks_identity_client_id="$(get_aks_identity_client_id)"

    echo "Generate service account password..."
    platform_service_account_password=$(get_or_generate_secret "platform-service-account-password")

    update_kubectl_cluster

    if helm status db-init &> /dev/null; then

      helm uninstall db-init
    fi

    helm install db-init azure/db-init \
      --set "azure.tenantId=${key_vault_tenant_id}" \
      --set "azure.secretProvider.keyvaultName=${key_vault_name}" \
      --set "azure.secretProvider.userAssignedIdentityClientID=${aks_identity_client_id}" \
      --set "keycloak.oasisRestApi.platformServiceAccount.password=${platform_service_account_password}"

    echo "Waiting for db init job to complete..."
    kubectl wait --for=condition=complete --timeout=60s job/db-init

    echo "Completed, job output:"
    kubectl logs job/db-init

    echo "Clean up job..."
    helm uninstall db-init
  ;;
  "get-acr")
    get_acr
  ;;
  "image"|"images")

    acr=$(get_acr)
    az acr login --name $acr

    echo "Deploying OasisPlatform images..."

    case "$2" in
    "server")

      pushd "${OASIS_PLATFORM_DIR}/"

      # Docker COPY issue https://github.com/moby/moby/issues/37965 - adds RUN true between COPY
      if [ "$TRUST_PIP_HOSTS" == "1" ]; then
        sed 's/pip install/pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' < Dockerfile.api_server | \
          sed 's/^COPY/RUN true\nCOPY/g' | \
          docker build -f - -t "${acr}/coreoasis/api_server:dev" .
      else
        sed 's/^COPY/RUN true\nCOPY/g' < Dockerfile.api_server | \
            docker build -f - -t "${acr}/coreoasis/api_server:dev" .
      fi

      docker push "${acr}/coreoasis/api_server:dev"
    ;;
    "worker-controller")

      pushd "${OASIS_PLATFORM_DIR}/"

      pushd "${OASIS_PLATFORM_DIR}/kubernetes/worker-controller"
      docker build -t "${acr}/coreoasis/worker_controller:dev" \
       --build-arg PIP_TRUSTED_HOSTS="pypi.org files.pythonhosted.org" .
      docker push "${acr}/coreoasis/worker_controller:dev"
    ;;
    "worker")

      pushd "${OASIS_PLATFORM_DIR}/"

      if [ "$TRUST_PIP_HOSTS" == "1" ]; then
        sed 's/pip3 install/pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org/g' < Dockerfile.model_worker | \
          sed 's/^COPY/RUN true\nCOPY/g' | \
          sed 's/^FROM ubuntu:20.10/FROM ubuntu:20.04/g' | \
          docker build -f - -t "${acr}/coreoasis/model_worker:dev" .
      else
         sed 's/^COPY/RUN true\nCOPY/g' < Dockerfile.model_worker | \
            sed 's/^FROM ubuntu:20.10/FROM ubuntu:20.04/g' | \
            docker build -f - -t "${acr}/coreoasis/model_worker:dev" .
      fi
      docker push "${acr}/coreoasis/model_worker:dev"
    ;;
    *)
      $0 image server
      $0 image worker-controller
      $0 image worker
      ;;
    esac
  ;;
  "cert-manager")

    echo "Deploying cert-manager..."

    update_kubectl_cluster

    # Check if cert-managers custom resource definitions exists

    if ! kubectl get crd -l app=cert-manager -l app.kubernetes.io/version=${CERT_MANAGER_CHART_VERSION} \
      2> /dev/null | grep -q certificaterequests.cert-manager.io; then

      echo "Applying cert-managers custom resource definitions..."
      kubectl apply -f ${SCRIPT_DIR}/cert-manager/crd-dependency/cert-manager-${CERT_MANAGER_CHART_VERSION}.crds.yaml
    fi

    helm_operation=""
    if ! helm status -n $CERT_MANAGER_NAMESPACE cert-manager &> /dev/null; then

      helm_operation=install
    else

      helm_operation=upgrade
    fi

    if [ "$helm_operation" == "install" ] || [ "$TF_BUILD" == "True" ]; then
      echo "Adding helm repository jetstack"
      helm repo add jetstack https://charts.jetstack.io
      helm repo update
    fi

    echo "Cert manager chart ${helm_operation}..."

    helm $helm_operation \
      cert-manager jetstack/cert-manager \
      --namespace $CERT_MANAGER_NAMESPACE \
      --create-namespace \
      --version $CERT_MANAGER_CHART_VERSION \
      -f "${SCRIPT_DIR}/settings/helm/cert-manager-values.yaml"
  ;;
  "oasis")

    echo "Deploying oasis..."

    echo "Retrieving oasis storage account name and keys"

    oasis_fs_account_name="$(get_secret oasisfs-name)"
    oasis_fs_account_key="$(get_secret oasisfs-key)"

    key_vault_name="$(get_key_vault_name)"
    key_vault_tenant_id="$(get_key_vault_tenant_id)"
    aks_identity_client_id="$(get_aks_identity_client_id)"

    oasis_database_host="$(get_secret oasis-db-server-host)"
    celery_redis_host="$(get_secret celery-redis-server-host)"

    update_kubectl_cluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/platform-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-platform/" "$HELM_PLATFORM_NAME" \
      --set "azure.storageAccounts.oasisfs.accountName=${oasis_fs_account_name}" \
      --set "azure.storageAccounts.oasisfs.accountKey=${oasis_fs_account_key}" \
      --set "azure.tenantId=${key_vault_tenant_id}" \
      --set "azure.secretProvider.keyvaultName=${key_vault_name}" \
      --set "azure.secretProvider.userAssignedIdentityClientID=${aks_identity_client_id}" \
      --set "databases.keycloak_db.host=${oasis_database_host}" \
      --set "databases.oasis_db.host=${oasis_database_host}" \
      --set "databases.celery_db.host=${oasis_database_host}" \
      --set "databases.channel_layer.host=${celery_redis_host}"

    echo "Waiting for controller to become ready..."
    kubectl wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

    echo "Environment: https://${domain}"
  ;;
  "summary")

    acr=$(get_acr)
    echo "Azure:"
    echo " Location:       $LOCATION"
    echo " Resource group: $RESOURCE_GROUP"
    echo " aks:            $aks"
    echo " acr:            $acr"
    echo
    echo "Environment:"
    echo " Front:          https://${domain}"
    echo " API:            https://${domain}/api/"
    echo " Prometheus:     https://${domain}/prometheus/"
    echo " Grafana:        https://${domain}/grafana/"
    echo " Alert-manager:  https://${domain}/alert-manager/"
    echo " Keycloak:       https://${domain}/auth/admin/master/console/"
    echo
    echo "Update kubectl:"
    echo " $ az aks get-credentials --resource-group $RESOURCE_GROUP --name $cluster_name"
    echo
    echo "Docker login:"
    echo " $ az acr login --name $acr"
  ;;
  "update-kubectl"|"update-kc")
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$cluster_name" --overwrite-existing
  ;;
  "models")

    echo "Deploying models..."

    chart_inputs="${SCRIPT_DIR}/settings/helm/platform-values.yaml ${SCRIPT_DIR}/settings/helm/models-values.yaml"
    for worker in "${SCRIPT_DIR}/settings/helm/workers/"*; do
      chart_inputs+=" $worker"
    done

    update_kubectl_cluster
    helm_deploy "${chart_inputs}" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-models/" "$HELM_MODELS_NAME" --set workers.piwind_demo=null

    echo "Waiting for models to be registered: "
    MODELS=$(cat $chart_inputs | grep modelId | sed 's/^[- \t]*modelId:[ ]*\([^ #]*\).*/\1/')

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

    update_kubectl_cluster
    helm_deploy "${SCRIPT_DIR}/settings/helm/monitoring-values.yaml" "${OASIS_PLATFORM_DIR}/kubernetes/charts/oasis-monitoring/" "$HELM_MONITORING_NAME"
  ;;
  "piwind-model-files")

    MODEL_PATHS="meta-data/model_settings.json oasislmf.json model_data/ keys_data/ tests/inputs/*.csv"
    OPTIONAL_MODEL_FILES="meta-data/chunking_configuration.json meta-data/scaling_configuration.json"
    files_to_copy=()

    for file in $MODEL_PATHS; do
      full_file="${OASIS_PIWIND_DIR}/$file"
      if ! [ -f "$full_file" ] && ! [ -d "$full_file" ] && ! ls $full_file &> /dev/null; then
        echo "Missing expected file: $full_file"
        exit 1
      fi
      echo "Found file: $full_file"
      files_to_copy+=("$file")
    done

    for file in $OPTIONAL_MODEL_FILES; do
      full_file="${OASIS_PIWIND_DIR}/$file"
      if [ -f "$full_file" ] && ! [ -d "$full_file" ]; then
        echo "Found optional file: $full_file"
        files_to_copy+=("$file")
      fi
    done

    update_kubectl_cluster
    $UPLOAD_MODEL_DATA -c "cp meta-data/* ." -C "$OASIS_PIWIND_DIR" OasisLMF/PiWind/1 ${files_to_copy[@]}
  ;;
  "analyses")

    start_port_forward_if_needed

    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/setup_env.sh \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceAccOEDPiWind.csv" \
          "${OASIS_PIWIND_DIR}/tests/inputs/SourceLocOEDPiWind.csv"

    stop_port_forward
  ;;
  "purge")

    case "$2" in
    "group"|"groups"|"resource-group")
      echo "Delete resource group: $RESOURCE_GROUP"
      az group delete -yn "$RESOURCE_GROUP"
    ;;
    "resources")
      resources="$(az resource list --resource-group "$RESOURCE_GROUP" | grep id | awk -F \" '{print $4}')"

      set +e
      for id in $resources; do
        az resource delete --resource-group "$RESOURCE_GROUP" --ids "$id" --verbose
      done
      set -e

      for id in $resources; do
        az resource delete --resource-group "$RESOURCE_GROUP" --ids "$id" --verbose
      done
    ;;
    "charts")
      for name in $(helm ls -q); do
        echo $name
        helm uninstall $name
      done
    ;;
    *)
      echo "$0 purge [group|resources]"
      exit 0
    esac
  ;;
  "api")

    start_port_forward_if_needed

    ${OASIS_PLATFORM_DIR}/kubernetes/scripts/api/api.sh "${@:2}"

    stop_port_forward
    ;;
  *)
    usage
    exit 1
  ;;
esac
