# Oasis on Azure

This document describes how to set up and manage the Oasis platform in Azure.

## Table of contents

- [Oasis on Azure](#oasis-on-azure)
  - [Table of contents](#table-of-contents)
  - [2.1 Prepare repository](#21-prepare-repository)
    - [2.1.1 Configuration](#211-configuration)
      - [Deploy script settings](#deploy-script-settings)
      - [Azure bicep parameters - settings/azure/parameters.json](#azure-bicep-parameters---settingsazureparametersjson)
      - [Helm settings](#helm-settings)
  - [2.2 Prepare DevOps pipeline](#22-prepare-devops-pipeline)
  - [2.3 Deploy the platform](#23-deploy-the-platform)
  - [2.4 Deploy PiWind](#24-deploy-piwind)
- [3 Use the platform](#3-use-the-platform)
  - [3.1 Manage your models](#31-manage-your-models)
    - [3.1.1 Step 1 - Upload model data](#311-step-1---upload-model-data)
      - [Use script](#use-script)
      - [Use Azure CLI](#use-azure-cli)
    - [3.1.2 Step 2 - Upload docker image](#312-step-2---upload-docker-image)
    - [3.1.3 Step 3 - Update Oasis models](#313-step-3---update-oasis-models)
  - [3.2 Types of deployments](#32-types-of-deployments)
  - [3.4 Run to verify](#34-run-to-verify)
  - [3.5 Monitoring](#35-monitoring)
    - [3.5.1 Load overview](#351-load-overview)
    - [3.5.2 Container logs](#352-container-logs)
    - [3.5.3 Alerts](#353-alerts)
    - [3.6 Configure worker scaling](#36-configure-worker-scaling)
      - [1 - Model](#1---model)
      - [2 - The worker deployments Kubernetes scheduling configuration.](#2---the-worker-deployments-kubernetes-scheduling-configuration)
      - [3 - The Azure Kubernetes nodes configuration.](#3---the-azure-kubernetes-nodes-configuration)
  - [4 Manage resource groups](#4-manage-resource-groups)
    - [4.1 View status](#41-view-status)
    - [4.2 Remove environment](#42-remove-environment)
    - [4.3 Delete all oasis enterprise resource groups](#43-delete-all-oasis-enterprise-resource-groups)
    - [4.4 Delete all resource groups](#44-delete-all-resource-groups)
  - [5 Deploy without the pipeline](#5-deploy-without-the-pipeline)
    - [5.1 Deploy platform](#51-deploy-platform)
    - [5.2 Deploy models](#52-deploy-models)
- [6 Secure the platform](#6-secure-the-platform)
  - [6.1 Default credentials](#61-default-credentials)
  - [6.2 Monitoring services](#62-monitoring-services)
    - [Base / Azure deployment gets stuck](#base--azure-deployment-gets-stuck)
- [8 Questions about design](#8-questions-about-design)
    - [Why is another resource group created?](#why-is-another-resource-group-created)
    - [Database users](#database-users)
    - [Celery on Azure Service Bus](#celery-on-azure-service-bus)
## 2.1 Prepare repository

An Azure DevOps pipeline is based on a repository and the first step is to clone/fork this repository and put it on a
place Azure DevOps can access it such as GitHub or bitbucket (check Azure DevOps for more alternatives). This gives us a
repository with everything we need to deploy Oasis and store our configurations.

```
git clone https://github.com/OasisLMF/OasisAzureDeployment.git
# Set origin and push to your repository
```

Then we need to set a few requires settings for our Azure environment. It is highly recommended going through all
configuration files (especially to secure it) but to deploy the environment you must set the following as a minimum:

-----------------------------

| File                           | Setting                   | Description                                                                                                             |
|--------------------------------|---------------------------|-------------------------------------------------------------------------------------------------------------------------|
| settings/settings.sh           | DNS_LABEL_NAME            | A unique name used to build the DNS name for this plaform                                                               |
| settings/settings.sh           | LETSENCRYPT_EMAIL         | Email used to generate the Let's Encrypt certificate. Will receive notifications if the certificate fail to be renewed. |
| settings/azure/parameters.json | allowedCidrRanges         | The IP address ranges that can access the platform.                                                                     |
| settings/azure/parameters.json | oasisServerAdminPassword  | The database administrator password                                                                                     | 


| WARNING: Please note that if you want to change the `workerNodesVm` setting this is not supported at the moment through the automatic deployment, instead you need to manually change it in the Azure Portal. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

More details about each setting is found below or in the files.

### 2.1.1 Configuration

There are 3 types of settings files to configuration the environment even more. Default settings are usually set to
resources of low/standard levels and can be updated to improve performance.

#### Deploy script settings

The file `settings/settings.sh` contains variables used by the `deploy.sh` script. Open the file for more details about
each variable and its values.

#### Azure bicep parameters - settings/azure/parameters.json

The file `settings/azure/parameters.json` contains Azure specific parameters like CIDR ranges, node types etc.

A short summary of the most interesting ones:

| Name                     | Description                                                                                                                                                                                                                                                                                                                                                 |
|--------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allowedCidrRanges        | Whitelisted [CIDR](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing) ranges - only these will be able to connect over HTTPS. Make sure to include the range/IP from where you will access the azure domain. The adress provided by [whatsmyip](https://www.whatsmyip.org) might work, but not always depending on your network access to Azure. |
| oasisServerAdminPassword | Password for database administrator account                                                                                                                                                                                                                                                                                                                 |
| platformNodeVm           | Type of Virtual Machine to use for the AKS platform node (run everything except for worker pods)                                                                                                                                                                                                                                                            |
| workerNodesVm            | Type of Virtual Machine to use for AKS worker nodes. **Warning: Please note this can't be changed after deployment due to lack of support in Azure deployments. You can still change it manually in the Azure Portal.**                                                                                                                                     |
| workerNodesMaxCount      | The limit of number of worker nodes to scale up. Will never exceed this number.                                                                                                                                                                                                                                                                             |
| oasisStorageAccountSKU   | Storage account disk class. Use premium class to increase file share I/O speed.                                                                                                                                                                                                                                                                             |
| clusterName              | AKS cluster name                                                                                                                                                                                                                                                                                                                                            |
| tags                     | Tags to attach to all resources created                                                                                                                                                                                                                                                                                                                     |
| openHttpForAll           | When set to `true` this will open up HTTP access without any filtering and redirect all requests to HTTPS. There are 2 reasons to have this open:<br>1. It is required for letsencrypt to create a valid TLS certificate.<br>2. Help some browsers to find the HTTPS service.                                                                               |
| availabilityZones        | List of availability zones to use in this Azure location.                                                                                                                                                                                                                                                                                                   |

#### Helm settings

Helm settings are used to configure our Helm charts, more specifically settings related to kubernetes resources and
deployed models. There is no need for changing them to deploy the platform, which will bring up a platform with a PiWind
model. But you need to change them later to change default passwords and add your models.

You can set chart values in `settings/helm`.

## 2.2 Prepare DevOps pipeline

Pipelines can't be automatically setup. We need to set up a project, a pipeline and two service connections to be able
to reach your repository and Azure. We also need to create our resource group and add permissions to it to let the
pipeline change it, but this only takes a few minutes.

Once you have logged into [Azure Devops](https://dev.azure.com):

1. Create a project:
    1. Click `New project`
    2. Give the project a name, such as Oasis platform, and click `Create`.
    3. Select your repository location and `Next`. If this is the first time you add this location it will start a guide
       to add it and authenticate against it.
    4. Select your repository and click `Next`.
    5. On the `Review your pipeline YAML` page just `Save` from the dropdown menu next to the `Run` button. We do not
       want to run it yet.
2. Set up Azure Service Connection:
    1. Click `Project settings` in bottom left corner.
    2. Click `Service connections`.
    3. Click `New service connection`.
    4. Select `Azure Resource Manager` and click `Next`.
    5. Select `Service principal (automatic)` and click `Next`.
    6. Select your subscription, give the service connection name `Azure Connection`,
       check `Grant access permission to all pipelines` and click `Save`.
    7. Repeat the same process to create a GitHub connection and name it "OasisLMF". 
3. Set up the pipeline service principal access:
    1. Open the default pipeline by clicking `Pipelines` in menu to the left and then the first pipeline in the list.
    2. Click `Run pipeline`.
    3. Select branch in case you are using another one than master.
    4. Select `resource-groups` from dropdown as `Deploy`.
    5. Click `Run`. This will create your resource groups set in your `settings.sh` file. In case you get a permission
       denied error, click the `Permission needed` link and `Permit`. The pipeline will continue after this.
    6. Wait for it to finish creating our resource group. You can check the progress and log by clicking the `Job`.
4. Give pipeline ownership of the resource group:
    1. Once again go to `Project settings`, `Service connections` and click `Azure Connection`.
    2. Click the link `Manage Service Principal` which opens a new tab to the Azure portal. Copy the `Display name`.
    3. In the Azure Portal go to `Resource groups` - either by selecting it from the meny or search for it in the top.
    4. Open the resource group name you defined in your configuration and just created.
    5. Click `Access control (IAM)` and then `Add role assignment` in `Grant access to this resource`.
    6. Select `Owner` and click `Next`.
    7. Click `+ Select members`.
    8. Paste the service principal name you copied in former step into the search field.
    9. Select the name in the list and click `Select`.
    10. Click `Next` and then `Review + assign`.

We do now have our resource group created and a pipeline ready!

## 2.3 Deploy the platform

Let's deploy the infrastructure and the platform:

1. In Azure DevOps click `Pipelines` in the menu to the left to bring up your pipelines.
2. The list should at this point only contain one, click that one.
3. Click `Run pipeline` in the top right.
4. Select `base` as `Deploy` and click `Run`.

This will deploy:

- Azure resources such as networks, Kubernetes cluster (AKS), key vault, databases etc.
- Cert-manager to automatically retrieve a valid TLS certificate from letsencrypt.
- Build and push oasis server and worker images from OasisPlatform/platform-2.0.
- Oasis Helm charts for the platform.

This initialization deployment may take up to 50 minutes to deploy (redis takes about 25-40 minutes for some reason).
You can follow the progress by opening up the job and view the `Deploy` task output. The deployment of Azure resources
can be monitored in more detail in the Azure Portal under `Deployments` in your resource group.

At the end it prints a summary of resource names and URLs. It might take a few minutes more before those URLs are
accessible due to the time kubernetes needs to initialize the Oasis platform.

The front will be available when all pods are `Running`. You can check this from your local machine (if you have Azure
cli and kubernetes installed):

```
# Update kubectl context
./deploy.sh update-kubectl

$ kubectl get pods
NAME                                                READY   STATUS    RESTARTS   AGE
broker-5754b57b78-kh8ql                             1/1     Running   0          4m7s
celery-beat-696ffc58f5-4c5zr                        1/1     Running   0          4m7s
celery-db-64fdbc8447-p9279                          1/1     Running   0          4m7s
channel-layer-66545898f7-ccqtq                      1/1     Running   0          4m7s
keycloak-6f84587755-pclr2                           1/1     Running   0          4m7s
keycloak-db-5cdd89bb8-5xj56                         1/1     Running   0          4m7s
oasis-server-5956dbc659-spcdd                       1/1     Running   0          4m7s
oasis-task-controller-548c74597b-jxlnd              1/1     Running   0          4m7s
oasis-ui-749447fb84-4sgmt                           1/1     Running   0          4m7s
oasis-worker-controller-6675bc8c6f-zwhjq            1/1     Running   0          4m7s
oasis-worker-monitor-57ff989d5-j9k6b                1/1     Running   0          4m6s
platform-ingress-nginx-controller-96d6f4c68-84jh6   1/1     Running   0          4m7s
server-db-6c6f464787-8gtzl                          1/1     Running   0          4m7s
```

Try to open the front URL from the `summary` and you should see the Oasis Web Front.

The Oasis platform is deployed to Azure!

Can't access the front? Check out the [Troubleshooting](#7-Troubleshooting) section for common errors.

At this point you can either deploy the PiWind model or your own to test the platform.

## 2.4 Deploy PiWind

The deployment option `piwind` lets you install the PiWind model, upload the data for it to run and have some analyses
created ready to be run.

1. Click `Run pipeline`.
2. Select `piwind` as deployment.
3. Click `Run`.

You are now ready to run your first analysis!

# 3 Use the platform

## 3.1 Manage your models

Three steps are requires to install your own model:

1. Upload model data to Azure (Azure Files).
2. Upload docker image to Azure (ACR).
3. Update `settings/helm/models-values.yaml`.

### 3.1.1 Step 1 - Upload model data

The platform has a specific file share for model data and requires a strict structure to automatically be found by
worker pods:

`<supplier>/<name>/<version>/model_settings.json`

The file `model_settings.json` is the only required file, but you do most likely want to put key/model data here as
well.

All files in this location will be mounted in the worker container on the path defined later in the helm chart values.

You can either upload your files directly in the Azure Portal, using the script in this repository or use the Azure
CLI (if your IP is in the CIDR range).

#### Use script

The `./scripts/upload_model_data.sh` script can be used to upload model data to the file share in Azure. It will work
even if your IP is not whitelisted by upload the files through the kubernetes cluster.

```
./scripts/upload_model_data.sh -C ../OasisPiWind/ OasisLMF/PiWind/1 meta-data/model_settings.json oasislmf.json model_data/ keys_data/
```

It will overwrite files but not remove any files.

#### Use Azure CLI

The Azure CLI can be used to upload files to the file share but requires your IP to be whitelisted in the CIDR range.

```
# Set name of key vault 

You can lookup the name of the keyvault on the Azure portal, or alternatively use az cli as below:

KEY_VAULT_NAME=$(az keyvault list --resource-group <YOUR_RESOURCE_GROUP_NAME> | jq -r '.[0].name')


# Get name and key for storage account
OASIS_FS_ACCOUNT_NAME="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-name --query "value" -o tsv)"
OASIS_FS_ACCOUNT_KEY="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name oasisfs-key --query "value" -o tsv)"

# Create your directories for your model
az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF"
az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF/PiWind"
az storage directory create --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models -n "OasisLMF/PiWind/1"

# Upload your model_settings.json file
az storage file upload --account-name "$OASIS_FS_ACCOUNT_NAME" --account-key "$OASIS_FS_ACCOUNT_KEY" --share-name models \
   --source model_settings.json --path "OasisLMF/PiWind/1/model_settings.json"
```

Checkout `az storage file upload-batch` for uploading directories.

### 3.1.2 Step 2 - Upload docker image

Build your image and upload it directly to ACR:

```
# Set your ACR
ACR=$(./deploy.sh get-acr)

# Login
az acr login --name $ACR

# Tag your images - the container registry path is all up to you to decided
docker tag myimage:v1 ${ACR}/workers/myimage:v1"

# And push
docker push ${ACR}/workers/myimage:v1"
```

### 3.1.3 Step 3 - Update Oasis models

The last step is to add the model to `settings/helm/models-values.yaml` which keeps the list of all models we would like
to have deployed to our environment.

Modify the existing PiWind model or add a new one to the `workers:` section. When ready, commit and push your changes to
your repository.

Open your web browser and go to Azure DevOps and run your pipeline with `models` as `Deploy`. This will register your
model with oasis.

## 3.2 Types of deployments

The pipeline supports a set of deployment types. Some of them like `resource-groups` and `base` probably only needs to
be run once, but other should be run whenever a settings or model needs to be updated.

| Deploy          | Description                                                                                                         |
|-----------------|---------------------------------------------------------------------------------------------------------------------|
| resource-groups | Creates a resource group to store all Oasis resources within                                                        |
| base            | Installs the infrastructure (Azure resources), cert-manager, oasis, grafana etc. and builds and push images to ACR. |
| piwind          | Uploads model data, registers the model and creates test analyses ready to run.                                     |
| models          | Install/uninstalls models based on models defined in settings/helm/models-values.yaml                               |
| azure           | Updates Azure resources and settings.                                                                               |
| oasis           | Updates Oasis chart settings.                                                                                       |
| images          | Builds latest images from OasisPlatform/platform-2.0 repository and uploads them to the ACR.                        |

## 3.4 Run to verify

Let's try to run something - the first analysis:

```
# List all analyses
./deploy.sh api ls

# Run one of them
./deploy.sh api run 1
```

`deploy.sh api` is just a wrapper for the `OasisPlatform/kubernetes/scripts/api/api.sh` script. The run should finish
with a `RUN_COMPLETED` within a few minutes.

## 3.5 Monitoring

Prometheus, alert manager and Grafana are still available as monitoring tools, but Azure do also give us some additional
ones based on metrics from the cluster and storage for log files.

### 3.5.1 Load overview

You can view an overview of load, cpu usage, memory usage etc by opening `Monitoring Insights` on
the `Kubernetes service`:

1. Open [Azure Portal](https://portal.azure.com)
2. Search / go to `Kubernetes services`
3. Open your cluster
4. Select `Insights` in the menu under `Monitoring`

The first view gives you a cluster overview, but you can narrow it down by Nodes, Pods and Containers by selecting
another tab.

### 3.5.2 Container logs

Azure supports two ways to investigate logs:

* Tail live logs.
* Query logs.

Live logs gives you no history but only new entries logged by the container from the time you start to view the live
logs:

1. In `Kubernetes service` for your cluster select `Workloads` from the menu nder `Kubernetes resources`.
2. Find your pod either trom the `Deployments` or `Pods` tab.
3. On the pod page select `Live logs` from the menu.

You can view historical logs by following the link `Looking for historical logs? View in Log Analytics` from
the `Live logs` page. This will open up the log query tool and show you recent log entries for this pod.

You can also open the log query tool by selecting `Logs` from the menu under `Monitoring` on your `Kubernetes service`
cluster page. This will bring up the log query tool with some examples to chose from as good starting points before
building your owns. As any cloud service you won't be able to view historical logs in plain text mode. All logs lines
are split and displayed separately. It is bad for reading a section of the log, but great for finding and analyse logs.

### 3.5.3 Alerts

The cluster will try to automatically recover from failures, but alerts can be used to inform you when this is not
possible. Many alert conditions are available such as CPU, memory cluster health etc.

Alerts can be created from the `Alert` page on your `Kubernetes Service` page.

### 3.6 Configure worker scaling

The number of workers started is controlled by the `oasis-worker-controller` and is based on 3 configurations:

#### 1 - Model

The models `chunking_configuration` and `scaling_configuration` configuration controls the number of chunks to split the
work into and how the `oasis-worker-controller` should scale the number of workers for each model. A few alternatives
are supported from creating a fixed number of workers as soon as the model is needed to dynamically create workers
depending on the number of chunks available.

These settings can either be set manually through the API or automatically by creating json files next to
the `model_settings.json` file. More details can be found in the `OasisPlatform` repository.

#### 2 - The worker deployments Kubernetes scheduling configuration.

This configuration is found in the `settings/helm/models-values.yaml` file and controls the way Kubernetes schedules
worker pods to nodes. By setting the `nodeAffinity` and `podAntiAffinity` you control on which nodes to schedule worker
pods and if a node supports multiple or single workers. When a new worker pod is created and no node is available Azure
will create a new one.

The default settings is to only allow workers to be scheduled to nodes with the `oasislmf/node-type=worker` label and
limit the number of workers to one per node.

More details about pod scheduling can be found in
the [Kubernetes documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/).

#### 3 - The Azure Kubernetes nodes configuration.

This configuration controls the hard limit of number of worker nodes allowed to be created. Even if a worker requests
100 nodes it will never create more nodes than specified by the number in `workerNodesMaxCount`
in `settings/azure/parameters.json`.

The default node limit is `2`.

## 4 Manage resource groups

### 4.1 View status

List resource groups and their status:

```
az group list --query '[].{name:name, state:properties.provisioningState}'
```

### 4.2 Remove environment

If you just want to delete one resource group:

```
az group delete --no-wait -yn <resource group>

# One additional is also created to group AKS resources
az group delete --no-wait -yn <resource group>-aks
```

This will do a "soft-delete" on the key vault, but to remove it permanently:

```
az keyvault list-deleted --query '[].name' -o tsv
az keyvault purge --name <key-vault-name>
```

### 4.3 Delete all oasis enterprise resource groups

```
az group list --tag oasis-enterprise=True --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

### 4.4 Delete all resource groups

```
az group list --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

## 5 Deploy without the pipeline

If you don't want to use a DevOps pipeline you can always use the deploy.sh script and deploy locally or use in another
pipeline.

### 5.1 Deploy platform

First make sure you are logged in with Azure CLI:

```
az login
```

Then run `deploy.sh` script:

```
# Create the group to place our resources in
./deploy.sh resource-group

# Create the platform
./deploy.sh base
```

The argument `base` will:

- Create necessary azure resources
- Build and push oasis/worker images
- Install cert-manager to automatically retrieve a valid certificate for TLS
- Install Oasis platform
- Write a summary of resource names and service urls

The summary lists the URL to each service as well as the kubectl command to update your cluster context to ACR.

Make sure all pods are started:

```
# Update your kubectl context to point to your new AKS cluster:
./deploy.sh update-kubectl

# List all pods and their status
kubectl get pods
```

Verify that our certificate is ready:

```
kubectl get certificate
```

If the certificate isn't ready within a few minutes please read the [Troubleshooting](#7-Troubleshooting) to investigate
the issue.

When the certificate is ready you should be able to access the front by pointing your web browser to the "Front" url
listed in the deployment output.

You do now have a platform running in Azure, but without any models.

### 5.2 Deploy models

Models are installed in the same way as through the pipeline, but instead of running the pipeline you run `deploy.sh`
with either `piwind` or `model`.

To install PiWind with one portfolio and some analyses run:

`./deploy.sh piwind`

To install your own model read [Manage your models](#3.1-Manage-your-models) and instead of running the pipeline
with `models` as deploy, run the script instead:

`./deploy.sh models`

# 6 Secure the platform

The platform will by default enforce TLS, encrypt data, generate database passwords etc. but there are still things to
secure to make it production ready. The level depends on your organizations needs.

If passwords are set correctly the standard deployment will be well secured and also allow you to use and manage the
platform easily through pipelines and scripts. But the bar can be raised if you want it to be even more secure.

## 6.1 Default credentials

One of the first thing to change are default passwords:

1. Keycloak admin user - the master password for Keycloak. Change it in the Keycloak admin console (URL path
   /admin/master/console/)
2. Oasis admin user - the default oasis user - change the password in Keycloak.

## 6.2 Monitoring services

The default deployment includes Prometheus, Alert manager and Grafana. You can change the default password for Grafana
but Prometheus and Alert manager does not have a login at all. But since Azure covers most functionality anyway we could
install Prometheus, Alert manager and Grafana unless there isn't any specific feature or better graph we want from it.

How to uninstall:

1. Remove the monitoring deploy from the `deploy.sh` script:

   ```
   case "$deploy_type" in
   "base")
   $0 azure
   $0 db-init
   $0 images
   $0 cert-manager
   $0 oasis
   $0 monitoring  <- Remove this line
   $0 summary
   ;;
   ...

   This will make sure it isn't installed.

2. If monitoring tools already are installed you can uninstall it by running `helm uninstall monitoring`

## 6.3 Internet access

The platform has a few points facing the internet:

- HTTP/HTTPS load balancer
- Key vault
- Storage account
- Container registry

Even if they are secured with encryption, IP filtering and Azure services there is always an elevated risk of having
them facing the internet. The platform can be completely isolated from the internet depending on your needs but requires
some changes beyond configuration in that case.

It is also worth noticing that if Azures key vault would be compromised you still would need to access the storage and
databases from either the kubernetes network or from an IP accepted by the CIDR settings.

### The load balancer

The load balancer has two internet facing service:

- HTTP - Open for all IPs. Does not provide any content or access to Oasis but is used to verify the domain and retrieve
  certificates from letsencrypt. Redirects all requests to HTTPS.
- HTTPS - Secured by valid certificate issued by letsencrypt and filters IP sources based on the `allowedCidrRanges`
  setting in `settings/parameters.json`.

Depending on your needs and your organizations limits and policies you can either keep it as it is, close down HTTP and
provide your own certificate or remove the internet completely and use private link and private dns to route your
company network to the Azure network.

### Azure resources

The cluster (oasis, celery, rabbitmq etc.) and databases runs isolated and is not accessible from internet. Key vault,
storage account and container registry is accessible from internet but requires credentials and encrypted connection.
The storage account is also IP filtered. The reason for not having a private link to these services is that
the `deploy.sh` and Azure cli won't be able to access and set up the resources on deployment. This could be changes
however after the deployment but will disable things like generating passwords and deploy new oasis images. But that
might not be required later depending on how you would like to maintain your system.

Some changes are required to enable private endpoints:

1. Call the `private_endpoint.bicep` module in `key_vault.bicep`, `registry.bicep` and `storage_account.bicep`. public
   access to these services will isolate them from the internet.
2. Replace `get_or_generate_secret` function calls with `get_secret` in `deploy.sh`.

## 6.4 CIDR configuration

Make sure to verify your CIDR configuration and only accept sources you trust.

# 7 Troubleshooting

### Deployment never finish or timeouts

The pipeline in Azure DevOps has a time limit on 60 minutes and will be stopped if it takes longer than that.

```
##[error]The job running on agent Hosted Agent ran longer than the maximum time of 60 minutes. For more information, see https://go.microsoft.com/fwlink/?linkid=2077134
```

If this happens it is most likely due to either:

- The creation of Redis takes too long.
- Azure gets stuck on one of the deployments.

You will find more details if you to `Deployments` in your resource group. Here you will find the list of deployments
and their statuses.

Even if the pipline fails due to the time limit the deployment may still finish successfully. If no deployment has
failed, leave it for a while and see if it finishes successfully. If not, try to cancel it and run the pipeline again.

You can run the pipeline again once the deployment has finished or been cancelled. It will verify the Azure deployment
and continue with the next step of setting up the environment.

### DNS name does not resolve

Try to recreate the ingress service to request the domain name again:

```kubectl delete service platform-ingress-nginx-controller```

And then deploy `oasis`.

### The web server is not responding

Make sure the UI pod is running:

```
kubectl get pod -l app=oasis-ui
NAME                           READY   STATUS    RESTARTS   AGE
oasis-ui-749447fb84-4sgmt      1/1     Running   0          5m
```

Also make sure to check your CIDR range configuration in `settings/parameters.json` and verify your IP is set correctly.

### Certificate never gets ready

Check the certificate status:

```
kubectl get certificate
```

The `READY` column should be `True` for `oasis-ingress-tls`. If it still is in `False` after a minute or so try to
delete it and retrieve a new certificate:

```
kubectl delete certificate oasis-ingress-tls
```

Wait another 30 seconds. If it still is `False` read the [troubleshooting guide](https://cert-manager.io/docs/faq/acme/)
to investigate the request.

### Base / Azure deployment gets stuck

Go to the `Azure Portal` -> `Resource Groups` -> `<your group>` -> `Deployments` to look for details about the
deployment process.

Please note that redis deployment can take up to 40 minutes and this is expected by Microsoft.

I have encountered errors in the AKS deployment such as `Gateway timeout` and `Internal server error`. I suspect this is
some error on Azures side and not with the bicep script itself. Try change location if you can, that usually solves the
issue.

# 8 Questions about design

### Why is another resource group created?

AKS will create its own resource group. More details can be
found [here](https://docs.microsoft.com/en-us/answers/questions/25725/why-are-two-resource-groups-created-with-aks.html)
and [here](https://github.com/Azure/AKS/issues/3).

### Database users

The `deploy.sh` script will create users with generated passwords, one for each database. Bicep/Azure does not support
this at deployment.

### Celery on Azure Service Bus

Celery is still using RabbitMQ as the broker running in the Kubernetes cluster. Celery has support (through kombu) for
Azure Service Bus but not very well reviewed/tested and with known issues. Due to this and the low volume of data sent
over celery RabbitMQ is kept for now.

More information can be
found [here](https://docs.celeryproject.org/projects/kombu/en/stable/reference/kombu.transport.azureservicebus.html) (
the Celery project site is currently at this point down and has been for the last 2 weeks)

There is however RabbitMQ products available
on [Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=rabbitmq) that might be a
good option, but as long as RabbitMQ runs fine in our cluster, I can't motivate the additional complexity and cost to
use these.
