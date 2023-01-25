# k8s-scheduler-demo
This is a repo to demo the Pod Scheduling in a Kubernetes/OpenShift cluster

## Requirements
You need a cluster with at least 3 worker nodes. 
You need cluster-admin rights, because you need to label and taint nodes.

## Execution
./setup.sh

A project demo-... will be created.  At the end of the demo the project will be removed.

# Features
- deploy multiple pod instances on different nodes
- restart failed pods
- deploy pods on a specific node
- deploy pods on a node with a specific HW/SW/... (eg GPU)
- set taints on a node
- set toleration to run on a node with a taint
- run on a node which is unschedulable (master)

# Some information about signals, kubectl delete pod...

Signals_and_kubectl.md