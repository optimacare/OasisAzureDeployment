# 1 - Oasis on Azure

This document describes how to set up and manage the Oasis platform in Azure by using Azure DevOps pipelines.

# 2 - Requirements

Before you begin, make sure you know check the requirements:

- [Azure](https://www.azure.com) subscription
- Azure account with enough privileges to create resources and assign roles

For DevOps pipeline:

- [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/) (for pipeline deployments)

For the ability to debug the environment:

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)

For deploying without a pipeline:

- [Helm](https://helm.sh)


# 3 - Setup environment

## 3.1 - Prepare repository

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

### 3.1.1 - Configuration

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


## 3.2 Prepare DevOps pipeline

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
   1. Open the default pipeline by clicking **Pipelines** in menu to the left and then the first pipeline in the list.
   2. Click **Run pipeline**.
   3. Select branch in case you are using another one than main.
   4. Select **resource-groups** from dropdown as **Deploy**.
   5. Click **Run**. This will create your resource groups set in your `settings.sh` file. In case you get a permission denied error, click the **Permission needed** link and **Permit**. The pipeline will continue after this. Wait for it to finish creating our resource group.
4. Give pipeline ownership of the resource group:
   1. Once again go to **Project settings**, **Service connections** and click **Azure Connection**.
   2. Click the link **Manage Service Principal**, copy the **Display name**.
   3. In the Azure Portal go to **Resource groups** - search in the top.
   4. Select the resource group name you defined in your configuration.
   5. Click **Access control (IAM)** and then **Add role assignment** in **Grant access to this resource**.
   6. Select **Owner** and click **Next**.
   7. Click **+ Select members**.
   8. Paste the service principal name you copied in former step into the search field.
   9. Select the name in the list and click **Select**.
   10. Click **Next** and then **Review + assign**.

We do now have our resource group created and a pipeline ready. Please note that if you add another resource group you need to repeat step 3 and 4.

## 3.3 - Deploy the platform

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

## 3.4 - Deploy PiWind

The deploy option **piwind** lets you install the PiWind model, upload the data for it to run and have some analyses created ready to be run.

1. Click **Run pipeline**
2. Select **piwind** as deployment.
3. Click **Run**

# 4 - Use the platform

## 4.1 - Manage your models

Models are managed by the `settings/helm/models-values.yaml` file and should be updated with the models you want to be available in your environment.

Three steps are requires to install your own model:

1. Upload model data to Azure (Azure Files).
2. Upload docker image to Azure (ACR).
3. Update `settings/helm/models-values.yaml`.

### 4.1.1 - Step 1 - Upload model data

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

### 4.1.2 - Step 2 - Upload docker image

Build your image and upload it directly to ACR:

```
# Set your ACR - found in the summary from the base deploy or if you run ./deploy.sh summary
ACR=acroasisenterprisedevops.azurecr.io

# Login
az acr login --name $ACR

# Tag your images - the container registry path is all up to you to decided
docker tag myimage:v1 ${ACR}/workers/myimage:v1"

# And push
docker push ${ACR}/workers/myimage:v1"
```

### 4.1.3 - Step 3 - Update Oasis models

The last step is to add the model to `settings/helm/models-values.yaml` which keeps the list of all models we would like to have deployed to our environment.

Modify the existing PiWind model or add a new one to the `workers:` section. When ready, commit and push your changes to your repository.

Open your web browser and go to Azure DevOps and run your pipeline with **models** as **Deploy**. This will register your model with oasis.

## 4.2 - Types of deployments

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

## 4.3 - Deploy without the pipeline

If you don't want to use a DevOps pipeline you can always use the deploy.sh script and deploy locally or use in another pipeline.

### 4.3.1 - Deploy platform

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

If the certificate isn't ready within a few minutes please read the [Troubleshoot](#5 - Troubleshoot) to investigate the issue.

When the certificate is ready you should be able to access the front by pointing your web browser to the "Front" url listed in the deployment output.

You do now have a platform running in Azure, but without any models.

### 4.3.2 - Deploy models

Models are installed in the same way as through the pipeline, but instead of running the pipeline you run `deploy.sh` with either `piwind` or `model`.

To install PiWind with one portfolio and some analyses run:

`./deploy.sh piwind`

To install your own model read [Manage your models](#4.1 - Manage-your-models) and instead of running the pipeline with `models` as deploy, run the script instead:

`./deploy.sh models`


## 4.4 - Run to verify

Let's try to run something - the first analysis:

```
# List all analyses
./deploy.sh api ls

# Run one of them
./deploy.sh api run 1
```

`deploy.sh api` is just a wrapper for the `OasisPlatform/kubernetes/scripts/api/api.sh` script. The run should finish with a `RUN_COMPLETED` within a few minutes.

## 4.5 - Manage resource groups

### 4.5.1 - View status

List resource groups and their status:

```
az group list --query '[].{name:name, state:properties.provisioningState}'
```

### 4.5.2 - Remove environment

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

### 4.5.3 - Delete all oasis enterprise resource groups

```
az group list --tag oasis-enterprise=True --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

### 4.5.4 - Delete all resource groups

```
az group list --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```

# 5 - Troubleshoot

### DNS name does not resolve

Try to recreate the ingress service to request the domain name again:

```kubectl delete service platform-ingress-nginx-controller```

And then deploy `oasis`.

### Certificate never gets ready

Check the certificate status:

```
kubectl get certificate
```

The `READY` column should be `True` for `oasis-ingress-tls`. If it still is in `False` after a minute or so try to delete it and retrieve a new certificate:

```
kubectl delete certificate oasis-ingress-tls
```

Wait another 30 seconds. If it still is `False` read the [troubleshooting guide](https://cert-manager.io/docs/faq/acme/) to investigate the request.


# 6 - Questions about design

### Why is another resource group created?

AKS will create its own resource group. More details can be found [here](https://docs.microsoft.com/en-us/answers/questions/25725/why-are-two-resource-groups-created-with-aks.html) and [here](https://github.com/Azure/AKS/issues/3).
