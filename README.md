We divided the project implementation into four stages:

1. We created Docker images for Kafka Confluent.
2. We developed and implemented a separate Kafka Cluster for the Unity project and used Helm to install it.
3. We developed a process to upgrade to the new version and integrate it with the standard Unity 2.0  monitoring subsystem ( Prometheus and Grafana ).
4. We conducted performance tests on the Kafka cluster.
