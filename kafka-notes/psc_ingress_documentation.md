# Private Service Connect (PSC) Ingress Documentation

**Producer:** `hsbc-11465671-unyin1-dev` (asia-south1)\
**Consumer:** `hsbc-11465671-unyin2-dev` (asia-south2)\
**VPCs:** Both use `hsbc-default-network`\
**PSC NAT subnets:** `psc-asia-south1`, `psc-asia-south2`

------------------------------------------------------------------------

# 📘 1. Architecture Overview

Below is the full flow of PSC between two private GKE clusters in prj1
and prj2.

                       +----------------------------------------------+
                       |         Project: prj1 (asia-south1)           |
                       |      VPC: hsbc-default-network (producer)     |
                       +----------------------------------------------+
                           | ILB (NGINX Ingress)
                           | 10.150.x.x
                           |
                 +---------v-----------+
                 | ServiceAttachment   |
                 | ingress-psc-sa      |
                 +---------+-----------+
                           |
                           | NAT using subnet psc-asia-south1
                           |
            ----------------------------------------------------------------
            |                              |                               |
            | PSC Endpoint (prj1)          | PSC Endpoint (prj2)           |
            | 10.50.0.10                   | 10.60.0.10                    |
            | region asia-south1           | region asia-south2            |
            ----------------------------------------------------------------
                           |                               |
                           |                               |
                   +-------v--------+              +-------v--------+
                   | GKE prj1       |              | GKE prj2       |
                   | Private Pods   |              | Private Pods   |
                   +----------------+              +----------------+

PSC ensures **private, non-routable, in-VPC-only connectivity** between
clusters.

------------------------------------------------------------------------

# 📘 2. Producer Setup (prj1 -- asia-south1)

## 2.1 Create PSC NAT Subnet

This subnet provides the **source NAT** for all PSC consumers.

``` bash
gcloud compute networks subnets create psc-asia-south1 \
  --project=hsbc-11465671-unyin1-dev \
  --region=asia-south1 \
  --network=hsbc-default-network \
  --range=10.200.0.0/24 \
  --purpose=PRIVATE_SERVICE_CONNECT
```

------------------------------------------------------------------------

## 2.2 NGINX Ingress Internal Load Balancer

`ingress-nginx-controller` service must be ILB:

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
    networking.gke.io/internal-load-balancer-allow-global-access: "true"
spec:
  type: LoadBalancer
  ports:
    - name: https
      port: 443
      targetPort: 443
  selector:
    app.kubernetes.io/name: ingress-nginx
```

Check ILB IP:

``` bash
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
```

------------------------------------------------------------------------

## 2.3 Create ServiceAttachment

``` bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gke.io/v1
kind: ServiceAttachment
metadata:
  name: ingress-psc-sa
  namespace: ingress-nginx
spec:
  connectionPreference: ACCEPT_AUTOMATIC
  natSubnets:
    - psc-asia-south1
  proxyProtocol: false
  resourceRef:
    kind: Service
    name: ingress-nginx-controller
EOF
```

Extract ServiceAttachment URI:

``` bash
kubectl -n ingress-nginx get serviceattachment ingress-psc-sa \
  -o jsonpath='{.status.serviceAttachment}'
```

Expected:

    projects/hsbc-11465671-unyin1-dev/regions/asia-south1/serviceAttachments/ingress-psc-sa

------------------------------------------------------------------------

# 📘 3. Consumer Setup (prj2 -- asia-south2)

## 3.1 Allocate PSC Endpoint IP

``` bash
gcloud compute addresses create psc-endpoint-ip-unyin2 \
  --project=hsbc-11465671-unyin2-dev \
  --region=asia-south2 \
  --subnet=hsbc-default-subnet \
  --addresses=10.60.0.10
```

------------------------------------------------------------------------

## 3.2 Create PSC Endpoint (Forwarding Rule)

``` bash
gcloud compute forwarding-rules create psc-endpoint-fr-unyin2 \
  --project=hsbc-11465671-unyin2-dev \
  --region=asia-south2 \
  --network=hsbc-default-network \
  --address=psc-endpoint-ip-unyin2 \
  --target-service-attachment=projects/hsbc-11465671-unyin1-dev/regions/asia-south1/serviceAttachments/ingress-psc-sa \
  --allow-psc-global-access
```

Check connection status:

``` bash
gcloud compute forwarding-rules describe psc-endpoint-fr-unyin2 \
  --project=hsbc-11465671-unyin2-dev \
  --region=asia-south2 \
  --format="value(pscConnectionStatus)"
```

Should output:

    ACCEPTED

------------------------------------------------------------------------

# 📘 4. DNS Setup

If your private DNS zone is hosted in `hsbc-11465671-unyin1-dev`, add:

    api.backend.internal.hsbc IN A 10.60.0.10

Command:

``` bash
gcloud dns record-sets transaction start \
  --project=hsbc-11465671-unyin1-dev \
  --zone=internal-zone
```

``` bash
gcloud dns record-sets transaction add 10.60.0.10 \
  --project=hsbc-11465671-unyin1-dev \
  --zone=internal-zone \
  --name=api.backend.internal.hsbc. \
  --ttl=30 \
  --type=A
```

``` bash
gcloud dns record-sets transaction execute \
  --project=hsbc-11465671-unyin1-dev \
  --zone=internal-zone
```

------------------------------------------------------------------------

# 📘 5. GKE Connectivity Test

From GKE pod in prj2:

``` bash
kubectl exec -it <pod> -n <ns> -- curl -vk https://api.backend.internal.hsbc/
```

------------------------------------------------------------------------

# 📘 6. Verification Checklist

  ----------------------------------------------------------------------------------------------------
  Component                Command                                            Expected
  ------------------------ -------------------------------------------------- ------------------------
  ServiceAttachment        `kubectl get serviceattachment -n ingress-nginx`   Ready + URI

  PSC Endpoint             `gcloud compute forwarding-rules describe ...`     ACCEPTED

  DNS                      `dig api.backend.internal.hsbc`                    Returns PSC IP

  Ingress                  `curl` from pod                                    200 OK
  ----------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# 📘 7. Summary

-   PSC NAT subnet must be in **producer VPC**.\
-   ServiceAttachment exposes the GKE Ingress ILB privately.\
-   prj2 consumes it using PSC endpoint with private IP.\
-   DNS provides clean hostnames for both clusters.\
-   No public IPs or routing required --- fully private.
