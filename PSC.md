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



Step 4: Create a Backend Service in Network A, Region A
gcloud compute backend-services create gke-control-plane-backend-service \
  --protocol TCP \
  --load-balancing-scheme INTERNAL \
  --region us-central1
  
Step 5: Create a Forwarding Rule for PSC in Network A, Region A
gcloud compute forwarding-rules create psc-forwarding-rule \
  --region us-central1 \
  --load-balancing-scheme INTERNAL \
  --network network-a \
  --backend-service gke-control-plane-backend-service \
  --ip-protocol TCP \
  --ports 443 \
  --address psc-internal-ip
  
Step 6: Create a Service Attachment in Network A, Region A
This step creates a service attachment that allows VMs from other networks to connect to the PSC endpoint.

gcloud compute service-attachments create psc-service-attachment \
  --region us-central1 \
  --producer-forwarding-rule psc-forwarding-rule \
  --connection-preference ACCEPT_AUTOMATIC


