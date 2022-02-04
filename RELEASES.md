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
* Deploy script to create and setup environment. (this will be migrated to a pipeline later)
* Setting/parameter files to configure the environment.
* Updated charts in `OasisPlatform` to support Azure.
* Deployment instructions.

**This covers the following in the functional summary:**
TODO: remove?
* Most of Kubernetes architecture (1.1) except for:
  * Ingress & API - ingress supported but split over two hostnames. Using one will require changes in either oasis ui
    or oasis server.
  * Health checks - basic checks in place, works very well but will be improved.
  * RabbitMQ / Mysql support - Current helm charts use redis / postgres.
* Model deployment (1.3)
