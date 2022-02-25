# Oasis on Azure

This document describes how to set up and manage the Oasis platform in Azure by using Azure DevOps pipelines.

# Requirements

1. Azure subscription
2. Azure account with enough privileges to create resources and assign roles
3. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
4. [Helm](https://helm.sh)
5. [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/) (for pipeline deployments)

# Setup environment

## Prepare repository

Azure DevOps pipelines are using repositories to run and we need to clone/fork this repository and put it on a place Azure DevOps can access it such as GitHub or bitbucket (check Azure DevOps for more alternatives). 

```
git clone https://github.com/OasisLMF/OasisAzureDeployment.git
# Set origin and push to your repository
```

Then we need to set a few requires settings for our Azure environment. It is highly recommended going through all configuration files but to deploy the environment you must set the following as a minimum:

| File                           | Setting            |
|--------------------------------|--------------------|
| settings/settings.sh           | DNS_LABEL_NAME     |
| settings/settings.sh           | LETSENCRYPT_EMAIL  |
| settings/settings.sh           | OASIS_PLATFORM_DIR |
| settings/settings.sh           | OASIS_PIWIND_DIR   |
| settings/azure/parameters.json | allowedCidrRanges  |

More details about each setting is found below or in the file.

### Configuration

There are 3 types of settings files to configuration the environment even more.

#### Deploy script settings

The file `settings/settings.sh` contains variables used by the `deploy.sh` script. Open the file for more details about each variable and its values.

#### Azure bicep parameters - settings/azure/parameters.json

The file `settings/azure/parameters.json` contains Azure specific parameters like CIDR ranges, node types etc.

A short summary of the most interesting ones:

| Name              | Description                                                                                                                                                                                                                                                                                                                                                 |
|-------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| allowedCidrRanges | Whitelisted [CIDR](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing) ranges - only these will be able to connect over HTTPS. Make sure to include the range/IP from where you will access the azure domain. The adress provided by [whatsmyip](https://www.whatsmyip.org) might work, but not always depending on your network access to Azure. |
| openHttpForAll    | When set to `true` this will open up HTTP access without any filtering and redirect all requests to HTTPS. There are 2 reasons to have this open:<br>1. It is required for letsencrypt to create a valid TLS certificate.<br>2. Help some browsers to find the HTTPS service.                                                                               |
| availabilityZones | List of availability zones to use in this Azure location.                                                                                                                                                                                                                                                                                                   |
| platformNodeVm    | Type of Virtual Machine to use for the AKS platform node (run everything except for worker pods)                                                                                                                                                                                                                                                            |
| workerNodesVm     | Type of Virtual Machine to use for AKS worker nodes.                                                                                                                                                                                                                                                                                                        |
| clusterName       | AKS cluster name                                                                                                                                                                                                                                                                                                                                            |
| tags              | Tags to attach to all resources created                                                                                                                                                                                                                                                                                                                     |

#### Helm settings

There is no need to change settings for Helm charts while testing, but you should change default passwords when deploying a real environment. You can set chart values in `settings/helm`.


## Prepare DevOps pipeline

Pipelines can't be automatically setup. We need to set up a project, a pipeline and two service connections to be able to reach your repository and Azure. We also need to create our resource group and add permissions to it to let the pipeline change it.

Once you have logged into [Azure Devops](https://dev.azure.com):

1. Create a project:
   1. Click **New project**
   2. Give the project a name, such as Oasis platform, and click **Create**.
   3. Select your repository location and **Next**. If this is the first time you add this location it will start a guide to add it and authenticate against it.  
   4. Select your repository and click **Next**.
   5. On the **Review your pipeline YAML** page just **Save** from the dropdown menu next to the **Run** button.
2. Set up Azure Service Connection:
   1. Click **Project settings** in bottom left corner.
   2. Click **Service connections**.
   3. Click **New service connection**.
   4. Select **Azure Resource Manager** and click **Next**.
   5. Select *Service principal (automatic)** and click **Next**.
   6. Select your subscription, give the service connection name `Azure Connection` and click **Save**.
3. Set up the pipeline service principal access:
   1. Open the default pipeline
   2. Click **Run pipeline**.
   3. Select branch in case you are using another one than main.
   4. Select **resource-groups** from dropdown as **Deploy**.
   5. Click **Run**. This will create your resource groups set in your `settings.sh` file. In case you get a permission denied error, click the **Permission needed** link and **Permit**. The pipeline will continue after this. Wait for it to finish.
4. Give pipeline ownership of resource group:
   1. Once again go to **Project settings**, **Service connections** and click **Azure Connection**.
   2. Click the link **Manage Service Principal**, copy the **Display name**.
   3. In the Azure Portal go to **Resource groups** - search in the top.
   4. Select the resource group name you defined in your configuration.
   5. Click **Access control (IAM)** and then **Add role assignment** in **Grant access to this resource**.
   6. Select **Owner** and click **Next**.
   7. Click **+ Select members**.
   8. Paste the name you copied in former step.
   9. Select the name in the list and click **Select**.
   10. Click **Next** and then **Review + assign**.

We do now have our resource group created and a pipeline ready. Please note that if you add another resource group you need to repeat step 3 and 4.

## Deploy the platform

Let's deploy the infrastructure and oasis:

1. From your projects pipeline page click **Run pipeline**.
2. Select **base** as **Deploy** and click **Run**. 

This will deploy:
 - Azure resources as virtual network, AKS, ACR etc.
 - Cert-manager to automatically retrieve a valid TLS certificate from letsencrypt.
 - Build and push oasis server and worker images from OasisPlatform/platform-2.0.
 - Oasis Helm charts for the platform.

This initialization deployment may take up to 20 minutes to run. You can follow the progress by opening up the job and view the **Deploy** task output.

At the end it prints a summary of resource names and URLs. It might take a few minutes more before those URLs are accessible due to the time kubernetes needs to initialize the Oasis platform.

The front will be available when all pods are `Running`:

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

Try to open the front URL from the summary and you should see the Oasis Web Front.

At this point you can either deploy the PiWind model or your own to test the platform.

## Deploy PiWind

The deploy option **piwind** lets you install the PiWind model, upload the data for it to run and have some analyses created ready to be run.


1. Click **Run pipeline**
2. Select **piwind** as deployment.
3. Click **Run**

# Use the platform

## Manage your models

Models are managed by the `settings/helm/models-values.yaml` file and should be updated with the models you want to be available in your environment.

Three steps are requires to install your own model:

1. Upload model data to Azure (Azure Files).
2. Upload docker image to Azure (ACR).
3. Update `settings/helm/models-values.yaml`.

### Upload model data

The platform has a specific file share for model data and requires a strict structure to automatically be found by worker pods:

`<supplier>/<name>/<version>/model_settings.json`

The file `model_settings.json` is the only required file, but you do most likely want to put key/model data there as well.

All files in this location will be mounted in the worker container on the path defined later in the helm chart values.

You can either upload your files directly in the Azure Portal or from cli:

```
# Set name of key vault - from settings/azure/parameters.json
KEY_VAULT_NAME=keyVaultName

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

### Upload docker image

Build your image and upload it directly to ACR:

```
# ACR Login - Use your ACR name (found in ./deploy.sh summary output)
ACR=acroasisenterprisedevops.azurecr.io
az acr login --name $ACR




```

TODO: Remove env from deploy.sh

## Types of deployments

The pipeline supports a set of deployment types. Some of them like **resource-groups** and **base** probably only needs to be run once, but other should be run whenever a settings or model needs to be updated.

| Deploy          | Description                                                                                                         |
|-----------------|---------------------------------------------------------------------------------------------------------------------|
| resource-groups | Creates a resource group to store all Oasis resources within                                                        |
| base            | Installs the infrastructure (Azure resources), cert-manager, oasis, grafana etc. and builds and push images to ACR. |
| piwind          | Uploads model data, registers the model and creates test analyses ready to run.                                     |
| models          | Install/uninstalls models based on models defined in settings/helm/models-values.yaml                               |
| azure           | Updates Azure resources and settings.                                                                               |
| oasis           | Updates Oasis chart settings.                                                                                       |
| images          | Builds latest images from OasisPlatform/platform-2.0 repository and uploads them to the ACR.                        |

## Deploy without the pipeline

TODO

----------------------------

## Configuration files

## Deploy

### Platform

First make sure you are logged in with Azure CLI:

```
az login
```

Then run `deploy.sh` script:

```
./deploy.sh all
```

The argument `all` will:

 - Create azure resources
 - Build and push oasis/worker images
 - Install cert-manager to automatically retrieve valid certificate
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

The `READY` column should be `True`. If it still is in `False` after a minute or so try to delete it and retreive a new:

```
kc delete certificate oasis-ingress-tls
```

Wait another 30 seconds. If it still is `False` read the [troubleshooting guide](https://cert-manager.io/docs/faq/acme/).

When the certificate is ready you should be able to access the front by pointing your web browser to the "Front" url listed in the deployment output.

You do now have a platform running in Azure, but without any models.

### Models

Models still need to be deployed in the same was as when setting up the Kubernetes cluster, and model data uploaded directly to the node. This will change when a shared storage is enabled between server and workers.

A script can be used to add PiWind by uploading model data, deploy the Oasis models chart and create 10 analyses ready to be run for the model:

```
./deploy.sh setup
```

### Run to verify

Let's try to run something - the first analysis:

```
./deploy.sh api run 1
```

`deploy.sh api` is just a wrapper for the `OasisPlatform/kubernetes/scripts/api/api.sh` script. The run should finish with a `RUN_COMPLETED` within a few minutes.

## Manage resource groups

### View status

List resource groups and their status:

```
az group list --query '[].{name:name, state:properties.provisioningState}'
```

### Remove environment

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

### Delete all oasis enterprise resource groups

```
az group list --tag oasis-enterprise=True --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

### Delete all resource groups

```
az group list --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

# Design

AKS will create its own resource group.
https://docs.microsoft.com/en-us/answers/questions/25725/why-are-two-resource-groups-created-with-aks.html
https://github.com/Azure/AKS/issues/3
