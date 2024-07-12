Reserve an internal IP range for the PSC endpoints in the GKE VPC:

gcloud compute addresses create my-psc-address \
    --global \
    --purpose=PRIVATE_SERVICE_CONNECT \
    --addresses=192.168.240.0 \
    --prefix-length=24 \
    --network=cinternal-vpc1-europe-west3-psc
