#!/bin/bash
#

SESSION=$1
NODE1=`oc get nodes -l node-role.kubernetes.io/worker -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | head -n 1`
NODE2=`oc get nodes -l node-role.kubernetes.io/worker -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | tail -n 1`

echo " "
echo "Deploy one pod on one node"
echo "--------------------------"

oc new-app --name demo --image openshift/hello-openshift >/dev/null
# oc patch deployment demo -p '{"spec": {"strategy": {"type": "Recreate"}}}'  >/dev/null
oc patch deployment/demo --type='json' -p='[{"op": "replace","path": "/spec/strategy", "value": {"type": "Recreate"}}]' >>/dev/null

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set resources (cpu/mem) to a limit which is not available"
echo "Pod cann't be started, waiting"
echo "------------------------------"

oc patch deployment demo -p '{"spec": {"template": {"spec": {"containers": [{"name": "demo","resources": { "requests": { "cpu": "10"}}}]}}}}'
sleep 5
oc get $(oc get pod -l deployment=demo -o NAME --no-headers) -o jsonpath={.status.conditions[0].message}

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set replicas to 3, run on different nodes"
echo "-----------------------------------------"

# oc patch deployment demo -p '{"spec": {"template": {"spec": {"containers": [{"name": "demo","resources": { "requests": { "memory": "100M"}}}]}}}}'
oc patch deployment/demo --type='json' -p='[{"op":"remove","path":"/spec/template/spec/containers/0/resources"}]' >>/dev/null

oc scale deployment/demo --replicas 3

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Destroying two pods"
echo "Pods will be restarted automatically"
echo "------------------------------------"

oc delete pod --wait=false `oc get pods -l deployment=demo --no-headers=true| grep demo -m 2| awk '{ print $1 }'`

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set nodeSelector to ${NODE1}"
echo "All pods are running on the same node!"
echo "--------------------------------------"

# oc patch deployment/demo --patch '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"compute-0"}}}}}'
oc patch deployment/demo --type='json' -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\", \
                         \"value\":{\"kubernetes.io/hostname\":\"$NODE1\"}}]"

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Remove nodeSelector from Deployment"
echo "All pods are running on different nodes!"
echo "----------------------------------------"

oc patch deployment/demo --type='json' -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/nodeSelector\"}]"

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set nodeSelector to GPU=available"
echo "Set Label on $NODE2"
echo "All pods are running on the same node"
echo "--------------------------------------------"

oc patch deployment/demo --type='json' -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\", \
                         \"value\":{\"GPU\":\"available\"}}]"
oc label node $NODE2 GPU=available

echo " "; echo " "; read -p "Press enter " a; clear

# remove label
oc label node $NODE2 GPU- >/dev/null
# remove nodeSeelector
oc patch deployment/demo --type='json' -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/nodeSelector\"}]" >/dev/null


echo " "
echo "Set taint on ${NODE1}"
echo "Pods will no longer run on ${NODE1}"
echo "-----------------------------------"

oc adm taint nodes ${NODE1} key1=value1:NoExecute

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set toleration on Deployment"
echo "Kill all Pods, so they are restarted on all Nodes"
echo "Taint is sill active on ${NODE1}!"
echo "----------------------------------"

oc patch deployment/demo --type='json' -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\", \
                         \"value\":[{\"key\": \"key1\", \
                         \"effect\": \"NoExecute\", \
                         \"operator\": \"Equal\", \
                         \"value\": \"value1\"}]}]"


echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "Set toleration on Deployment for master: Unschedulable"
echo "Set nodeSelector on Deployment to master"
echo "All Pods will run on Master Nodes"
echo "---------------------------------"

# remove taint
oc adm taint nodes $NODE1 key1- >/dev/null

# accept all taints!
oc patch deployment/demo --type='json' -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/tolerations\", \
                         \"value\":[{\"operator\": \"Exists\"}]}, \
                {\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\", \
                         \"value\":{\"node-role.kubernetes.io/master\":\"\"}}]"

echo " "; echo " "; read -p "Press enter " a; clear

echo " "
echo "End of the demo"
echo " "
echo "Delete Deployment. All Pods will go"
echo "-----------------------------------"

oc delete all -l app=demo

# echo "$SESSION"

echo " "; echo " "; read -p "End of Demo. Press enter " a; clear

tmux kill-session -t $SESSION
