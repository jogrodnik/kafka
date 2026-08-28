gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c








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
    --region=europegcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c

  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
-west3 \
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
  --network network-gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internalgcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c

  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
a \gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c

  --backend-service gke-control-plane-backend-service \
  --ip-protocol TCP \
  --ports 443 \gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c

  --address psc-internal-ip
  
Step 6: Create a Servigcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
ce Attachment in Network A, Region A
This step creates a service attachment that allows VMs from other networks to connect to the PSC endpoint.

gcloud compute service-attachments create psc-service-attachment \
  --region us-central1gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
 \gcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zonegcloud dns record-sets transaction start \
  --zone=internal-zone \
  --project=project-c

# Remove old CNAME pointing to project-a
gcloud dns record-sets transaction remove \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-a.internal."

# Add new CNAME pointing to project-b
gcloud dns record-sets transaction add \
  --name="kafka-0.ns1.internal.com." \
  --type=CNAME \
  --ttl=30 \
  --zone=internal-zone \
  --project=project-c \
  --rrdatas="ingress.kafka-0.ns1.project-b.internal."

gcloud dns record-sets transaction execute \
  --zone=internal-zone \
  --project=project-c
 \
  --project=project-c

  --producer-forwarding-rule psc-forwarding-rule \
  --connection-preference ACCEPT_AUTOMATIC


