Reserve an internal IP range for the PSC endpoints in the GKE VPC:

gcloud compute addresses create psc-address \
    --global \
    --purpose=PRIVATE_SERVICE_CONNECT \
    --addresses=192.168.240.0 \
    --prefix-length=24 \
    --network=hsbc-11465671-dev-cinternal-vpc1
    
Create a PSC endpoint for the GKE control plane in the GKE subnetwork:

gcloud compute forwarding-rules create my-psc-forwarding-rule \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --address=psc-address \
    --target-service=gke-control-plane-endpoint \
    --subnet=cinternal-vpc1-europe-west3-gkenodes \
    --region=europe-west3 \
    --network=hsbc-11465671-dev-cinternal-vpc1 \
    --ports=443
