# kubectl delete deployment busybox
# kubectl delete pvc busybox-storage

cat << EOF | kubectl apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: busybox-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  volumeMode: Filesystem
EOF

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
          volumeMounts:
            - name: busybox-storage
              mountPath: /usr/busybox
      volumes:
        - name: busybox-storage
          persistentVolumeClaim:
            claimName: busybox-storage
EOF

