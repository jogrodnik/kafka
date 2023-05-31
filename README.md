We divided the project implementation into four stages:

1. We created Docker images for Kafka Confluent.
2. We developed and implemented a separate Kafka Cluster for the Unity project and used Helm to install it.
3. We developed a process to upgrade to the new version and integrate it with the standard Unity 2.0  monitoring subsystem ( Prometheus and Grafana ).
4. We conducted performance tests on the Kafka cluster.

Kafka instalation

Kafka Installation on Kubernetes
This guide provides step-by-step instructions for installing Apache Kafka on Kubernetes.

Prerequisites
Before you begin, ensure that you have the following prerequisites:

Kubernetes cluster up and running
kubectl command-line tool installed and configured to communicate with your cluster
Step 1: Create Kafka Namespace
Create a namespace for Kafka deployment:

bash
Copy code
kubectl create namespace kafka
Step 2: Deploy ZooKeeper
ZooKeeper is a prerequisite for Kafka. Deploy a ZooKeeper instance using the following command:

bash
Copy code
kubectl apply -f zookeeper.yaml -n kafka
Note: Make sure you have the zookeeper.yaml file, which contains the ZooKeeper deployment configuration.

Step 3: Deploy Kafka
Deploy the Kafka cluster using the following command:

bash
Copy code
kubectl apply -f kafka.yaml -n kafka
Note: Make sure you have the kafka.yaml file, which contains the Kafka deployment configuration.

Step 4: Verify Kafka Deployment
Wait for the Kafka deployment to be ready:

bash
Copy code
kubectl get pods -n kafka
Ensure that all Kafka pods are in the Running state before proceeding.

Step 5: Access Kafka
To access Kafka, you need to expose it as a Kubernetes service:

bash
Copy code
kubectl expose deployment kafka --type=LoadBalancer --port=9092 --name=kafka-service -n kafka
Step 6: Test Kafka
You can now test Kafka by connecting to the Kafka service. Get the external IP of the Kafka service:

bash
Copy code
kubectl get services kafka-service -n kafka
Use the obtained external IP and the port (9092 by default) to connect to Kafka from your Kafka clients or applications.

Step 7: Cleanup
To clean up the Kafka deployment, you can delete the Kafka namespace:

bash
Copy code
kubectl delete namespace kafka
Warning: This will delete all resources associated with the Kafka deployment. Make sure to back up any important data before performing this step.

Conclusion
You have successfully installed Kafka on Kubernetes. You can now use Kafka to build scalable and distributed streaming applications.

For more information and advanced configurations, please refer to the Kafka documentation.

Feel free to reach out if you have any questions or encounter any issues during the installation process.



#!/bin/bash

# Kafka connection details
bootstrap_servers="your_kafka_bootstrap_servers"
topic="your_topic_name"

# Test configuration
num_messages=10000
message_size_bytes=1000

# Create test messages
test_message="test_message$(seq -s ' ' -f '%.0f' 1 $((message_size_bytes/12)))"
test_messages=$(yes "$test_message" | head -n $num_messages)

# Produce test messages to Kafka
echo "$test_messages" | kafka-console-producer.sh \
  --bootstrap-server "$bootstrap_servers" \
  --topic "$topic" \
  --compression-codec snappy \
  --batch-size 1000 \
  --request-timeout-ms 30000

# Consume test messages from Kafka
kafka-console-consumer.sh \
  --bootstrap-server "$bootstrap_servers" \
  --topic "$topic" \
  --from-beginning \
  --timeout-ms 30000 \
  --max-messages "$num_messages"

The primary objective of the project was to establish dedicated clusters for each Unity project. By deploying a fully functional Kafka cluster within the Google Kubernetes Engine (GKE) environment, specifically tailored to each project, we could effectively optimize the internal communication among the services constituting the Unity 2 pipeline system.

During the project implementation, our aim was to preserve an on-premises cluster to ensure the consistent availability of data for both Unity 1 and Unity 2 systems. Additionally, this approach catered to projects where data processing within the Google Cloud Platform (GCP) environment was not feasible or compliant with specific requirements.


The project code has been stored in two Git repositories:
    1. unitycore-docker-confluent
    2. unitycore-gke-confluent
The unitycore-docker-confluent repository contains the implementation of Docker images that create an environment to build a Confluent Kafka system. This environment includes essential components such as a ZooKeeper cluster, brokers, and a schema registry. It enables the easy deployment of a fully functional Confluent Kafka system on a GKE cluster.
In the unitycore-gke-confluent repository, you'll find the implementation of Helm charts that automate the installation process specifically designed for the Unity project's Kafka cluster. This cluster is integrated with a comprehensive monitoring system based on the Prometheus/Grafana stack. The cluster is also secured using SSL protocols. Optionally, there are configurable parameters that allow access to the cluster through ingress controllers, making it more flexible and customizable for different deployment scenarios.
