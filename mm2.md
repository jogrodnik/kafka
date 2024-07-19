

# Source cluster configuration
src.consumer.isolation.level: read_committed
src.consumer.transactional.id: "mirror-maker-source-1-transaction"


# Target cluster configuration
dst.producer.acks: all
dst.producer.retries: 5
dst.producer.transactional.id: "mirror-maker-target-1-transaction"
dst.producer.transaction.timeout.ms: 60000
