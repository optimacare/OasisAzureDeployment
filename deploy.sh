#!/bin/bash

set -e

# Required settings
LOCATION="eastus2"
DNS_LABEL_NAME="aashouroasis"
LETSENCRYPT_EMAIL="ayman@climateguardinsurance.com"
RESOURCE_GROUP="oasis-enterprise"

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

  for file in "${temporary_files[@]}";
