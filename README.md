# Oasis on Azure

Check the requirements, configure your deployment and deploy the platform.

## Requirements

1. Azure subscription
2. Azure account with enough privileges to create resources
3. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
4. [Helm](https://helm.sh/) 

## Configuration files

It is highly recommended going through all configuration files but to deploy the environment you must set the following: 

| File                           | Setting            |
|--------------------------------|--------------------|
| settings/settings.sh           | DNS_LABEL_NAME     |
| settings/settings.sh           | LETSENCRYPT_EMAIL  |
| settings/settings.sh           | OASIS_PLATFORM_DIR |
| settings/settings.sh           | OASIS_PIWIND_DIR   |
| settings/azure/parameters.json | allowedCidrRanges  |

More details about each setting is found below or in the file.

### Deploy script settings

The file `settings/settings.sh` contains variables used by the `deploy.sh` script. Open the file for more details about each variable and its values.

### Azure bicep parameters - settings/azure/parameters.json

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

### Helm settings

There is no need to change settings for Helm charts while testing, but you should change default passwords when deploying a real environment. You can set chart values in `settings/helm`.


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
az group delete -yn <resource group>

# One additional is also created to group AKS resources
az group delete -yn <resource group>-aks
```

### Delete all resource groups

```
az group list --query [].name -o tsv | xargs -otl az group delete --no-wait -yn
```
