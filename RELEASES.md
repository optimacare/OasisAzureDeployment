# Release notes

## Sprint 1

Released on 2022-02-11

**Features included:**

* Bicep templates to create an Azure Oasis environment, which includes among other things:
  * Virtual network
  * Azure Kubernetes Service (AKS)
  * Azure Container Registry (ACR)
  * Load Balancer
  * Letsencrypt as provider of valid TLS certificate
  * CIDR filtering
* Deploy script to create and setup environment.
* Setting/parameter files to configure the environment.
* Updated charts in `OasisPlatform` to support Azure chart settings.
* Deployment instructions.

## Sprint 2

Released on 2022-02-25

**Features included:**
* Bicep templates and Helm chart values updated to include:
  * Storage account and 2 file shares: oasisfs and models.
  * Place worker on worker nodes:
  * Support scaling of worker nodes.
  * Key vault to store storage account key.
  * General cleanup and improvements regarding naming.
* Deploy script updated to support pipeline deployments.
  * General improvements regarding parameters, configuration and deployment names.
  * Tunnel Oasis API requests (to avoid https cidr filter on domain name)
* Updated charts in `OasisPlatform`:
  * Azure files support.
  * Update Prometheus stack to version 32.3.0.
* Updated deployment instructions (README.md):
  * Setup and use DevOps pipeline
  * Deploy models
  * Deploy without using pipeline
  * Cleanup and troubleshoot

