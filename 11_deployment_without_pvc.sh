cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
  labels:
    app: busybox
spec:
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      containers:
      - command: [ "/bin/sh", "-c", "while true ; do date -u +%R:%S; sleep 1; done;" ]
        image: busybox
        name: busybox
EOF