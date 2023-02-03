#! /bin/bash

zone=europe-west2-a
cluster

kubectl create serviceaccount gke-service-account --namespace default
kubectl annotate serviceaccount gke-service-account \
    --namespace default \
    iam.gke.io/gcp-service-account=gke-service-account-reportzen@pol-reportzen-dev-005.iam.gserviceaccount.com


gcloud container clusters get-credentials gke-reportzen-1 --zone=$zone

gcloud projects add-iam-policy-binding pol-reportzen-dev-005 \
    --member "serviceAccount:gke-service-account-reportzen@pol-reportzen-dev-005.iam.gserviceaccount.com" \
    --role "roles/cloudsql.editor"

gcloud iam service-accounts add-iam-policy-binding gke-service-account-reportzen@pol-reportzen-dev-005.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:pol-reportzen-dev-005.svc.id.goog[default/gke-service-account]"

#kubectl create secret generic gcp-secret-microgiants\
#  --from-literal=username=<YOUR-DATABASE-USER> \
#  --from-literal=password=<YOUR-DATABASE-PASSWORD> \
#  --from-literal=database=<YOUR-DATABASE-NAME>

https://cloud.google.com/sql/docs/mysql/connect-kubernetes-engine


