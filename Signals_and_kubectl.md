# Can a simple "delete pod" corrupt your database?

Everything started with a recent customer call. 
He explaind me that he had a (database) pod going wild...
As he did not found any other solution at the end he made a "kubectl/oc delete pod".
After that he found out that the database was corrupted.

We all know databases are able to survive a pod crash or a node crash when it is setup correctly.

If you what to know what heppend, why the database was corrupted at the end and how to avoid it. 
Please read the following blog.
BTW this can happend to every stateful pod!

# Signals and "kubctl/oc delete" command
Signals are essentially a standardized message sent to a process. Processes can generally decide how they want to handle different signals (except SIGKILL and SIGSTOP), but there’s some standardization. 
Sending a SIGTERM to a process gives it a chance to gracefully terminate. The process will usually execute some cleanup tasks and then exit. 
Sending a SIGKILL to a process will immediately terminate the process, giving it no opportunity to clean up after itself.

We ideally wanted to send a SIGKILL to our Kubernetes/OpenShift pods to test how they behave in ungraceful shutdown scenarios. 
The kubectl delete command is used to delete resources, such as pods. It provides a --grace-period flag, ostensibly for allowing you to give a pod a certain amount of time to gracefully terminate (SIGTERM) before it’s forcibly killed (SIGKILL). 
If you review the help menu for kubectl delete, you’ll find the following relevant bits:
```
    --force=false:
	If true, immediately remove resources from API and bypass graceful deletion. Note that immediate deletion of
	some resources may result in inconsistency or data loss and requires confirmation.

    --grace-period=-1:
	Period of time in seconds given to the resource to terminate gracefully. Ignored if negative. Set to 1 for
	immediate shutdown. Can only be set to 0 when --force is true (force deletion).

    --now=false:
	If true, resources are signaled for immediate shutdown (same as --grace-period=1).

```

## Test enviroment
OpenShift cluster 4.12 / Kubernetes 1.25.4 / CRIO 1.25.1 running.
 
Opening two terminal windows
- connected to the OpenShift cluster with one test project available
- connect into the node where the pod will be started
If you don't know, following command will show you the node name.
```bash
$ kubectl get pod -o wide
NAME                                        READY   STATUS    RESTARTS   AGE     IP            NODE        NOMINATED NODE   READINESS GATES
busybox                                     1/1     Running   0          8s      10.128.2.49   compute-2   <none>           <none>
```
You can also set a nodeSelector to specify the node.

On OpenShift you can use **oc debug node/...**

```
$ oc debug node/$(oc get pod busybox -o jsonpath='{.spec.nodeName}') -- chroot /host sudo -i sh -c 'whoami'
Warning: would violate PodSecurity "baseline:v1.24": host namespaces (hostNetwork=true, hostPID=true), hostPath volumes (volume "host"), privileged (container "container-00" must not set securityContext.privileged=true)
Starting pod/compute-2-debug ...
To use host binaries, run `chroot /host`
root

Removing debug pod ...
```

## kubectl delete pod

Make a simple ** kubectl delete pod** and have a look what happens.

Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
14:55:28
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template {{.info.pid}} `crictl ps --name busybox -q `) --absolute-timestamps
strace: Process 405764 attached
14:57:27 restart_syscall(<... resuming interrupted clock_nanosleep ...>) = ? ERESTART_RESTARTBLOCK 
```

Terminal 1:
```bash
$ date -u +%R:%S && kubectl delete pod busybox 
14:57:31
pod "busybox" deleted
```

Terminal 2:
```bash
(Interrupted by signal)
14:57:31 --- SIGTERM {si_signo=SIGTERM, si_code=SI_USER, si_pid=0, si_uid=0} ---
14:57:31 restart_syscall(<... resuming interrupted restart_syscall ...>) = ?
14:58:01 +++ killed by SIGKILL +++
```

Thirty seconds between receiving a SIGTERM and finally terminating via SIGKILL. Default behavior.

With .spec.terminationGracePeriodSeconds you are able to define a different garceperiod.
```
Optional duration in seconds the pod needs to terminate gracefully. May be decreased in delete request. Value must be non-negative integer. The value zero indicates stop immediately via the kill signal (no opportunity to shut down). If this value is nil, the default grace period will be used instead. The grace period is the duration in seconds after the processes running in the pod are sent a termination signal and the time when the processes are forcibly halted with a kill signal. Set this value longer than the expected cleanup time for your process. Defaults to 30 seconds.
```

On OpenShift you can directly run the strace via **oc debug node**... Much simpler.

```bash
$ oc debug node/$(oc get pod busybox -o jsonpath='{.spec.nodeName}') -- chroot /host sudo -i sh -c 'strace -p $(crictl inspect --output go-template --template {{.info.pid}} `crictl ps --name busybox -q`) --absolute-timestamps'
Starting pod/compute-2-debug ...
To use host binaries, run `chroot /host`
strace: Process 454448 attached
10:13:28 restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
10:13:44 --- SIGTERM {si_signo=SIGTERM, si_code=SI_USER, si_pid=0, si_uid=0} ---
10:13:44 restart_syscall(<... resuming interrupted restart_syscall ...>) = ?
10:14:14 +++ killed by SIGKILL +++

Removing debug pod ...
```

## kubectl delete pod --grace-period=1

Now we set the grace-period to one second.

Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
15:16:48
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template {{.info.pid}} `crictl ps --name busybox -q`) --absolute-timestamps
strace: Process 420839 attached
15:16:55 restart_syscall(<... resuming interrupted clock_nanosleep ...>) = ? ERESTART_RESTARTBLO 
```

Terminal 1:
```bash
$ date -u +%R:%S && kubectl delete pod busybox --grace-period=1
15:17:07
pod "busybox" deleted
```

Terminal 2:
```bash
15:17:08 --- SIGTERM {si_signo=SIGTERM, si_code=SI_USER, si_pid=0, si_uid=0} ---
15:17:08 restart_syscall(<... resuming interrupted restart_syscall ...>) = ?
15:17:09 +++ killed by SIGKILL +++
```

Notice that a SIGTERM is received, followed by a SIGKILL one second later. This is expected behavior, but it is not an immediate shutdown.
 
This is exact the same behavior as you are using **kubectl delete pod ... --now**

## kubectl delete pod --grace-period=0 --force=true

Set the grace-period to 0 seconds and force to true as documented.

Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
15:29:00
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template {{.info.pid}} `crictl ps --name busybox -q`) --absolute-timestamps
strace: Process 430015 attached
15:29:07 restart_syscall(<... resuming interrupted clock_nanosleep ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
```

Terminal 1:
```bash
$ date -u +%R:%S && kubectl delete pod busybox --grace-period=0 --force=true
15:30:01
pod "busybox" deleted
```

Terminal 2:
```bash
15:30:02 --- SIGTERM {si_signo=SIGTERM, si_code=SI_USER, si_pid=0, si_uid=0} ---
15:30:02 restart_syscall(<... resuming interrupted restart_syscall ...>) = ?
15:30:32 +++ killed by SIGKILL +++
```

Thirty seconds between receiving a SIGTERM and finally terminating via SIGKILL! That doesn’t sound like --grace-period=0 to me. So it turns out that specifying --grace-period=0 and --force=true might actually provide more of a grace period than you would expect.

Only the pod is removed, but the process does not receive a SIGKILL before the end of the grace-period . (attantion terminationGracePeriodSeconds). You are not able to send a second kubctl delete pod.

## crictl stop

The only way to realy kill a pod is currecntly **crictl stop **.

You have to open another terminal on the node...

```bash
# date -u +%R:%S && crictl stop $(crictl ps --name busybox -q)
16:00:17
ea5a7305e8d88
```

or via ** oc debug node** direct.
```bash
$ date -u +%R:%S && oc debug node/$(oc get pod busybox -o jsonpath='{.spec.nodeName}') -- chroot /host sudo -i sh -c 'crictl stop $(crictl ps --name busybox -q )'
Starting pod/compute-2-debug ...
To use host binaries, run `chroot /host`
78ed855d13a19b3d2c6b6d54dc9969e715894e8fffec937dd833640973c47d5b

Removing debug pod ...
```

```
16:00:17 +++ killed by SIGKILL +++
```

This command send directly a SIGKILL.

## Summery kubectl delete pod

A Pod "kill" works only with **--grace-period=1** (nearly one secound delay) with Kubernetes cmd and/or API.

An Kubernetes issue was opened almost two years ago pointing out that behavior. But in the meantime it is autoclosed. :-( 
https://github.com/kubernetes/kubernetes/issues/86914
Another Kubernetes issue reports that **--force** only deletes the pod, but the kublet doesn't kill the process.
```
Apiserver will immediately delete pod information from etcd. But kubelt does not accept requests with a grace period of 0. If the grace period is 0, the default value (usually 30s) is used as the time to interact with CRI. That's why the forced deletion fails.
```
https://github.com/kubernetes/kubernetes/issues/113717

## Deployment without PVC

Now lets test what happens when you are using a Deployment or Deployment Config (OpenShift). Kubelet will automatically restart the pod.

Terminal 1:
```bash
$ ./11_deployment_without_pvc.sh

```

Terminal 2: we will open the log of the running pod
```bash
$ oc logs $(oc get pod -l app=busybox -o NAME) -f
...
12:23:22
12:23:23
12:23:24
12:23:25
12:23:26
12:23:27
12:23:28
...
```

Termianl 1: we will delete the pod and look at the log of the new pod
```bash
$ date -u +%R:%S && kubectl delete $(oc get pod -l app=busybox -o NAME); sleep 5; oc logs $(oc get pod -l app=busybox -o NAME)
12:23:54
pod "busybox-754b65bfd6-vx88d" deleted
12:23:58
12:23:59
12:24:00
12:24:01
12:24:02
12:24:03
...
12:24:23
12:24:24
12:24:25
12:24:26
12:24:27
12:24:28
12:24:29
12:24:30
12:24:31
12:24:32
```

Terminal 2: we can see the end of the log of the first pod
```bash
12:23:53
12:23:54
12:23:55
12:23:56
12:23:57
12:23:58
12:23:59
...
12:24:21
12:24:22
12:24:23
12:24:24
12:24:25
```

We can clearly see that the pod was deleted at 12:23:54. Due to the grace-period earlier shown the first pod terminates at 12:24:25. And the newly created pod starts at 12:23:58.
So we have **two** pods running at the same time!
When we would delete the pod with --grace-period=1 or set the terminationGracePeriodSeconds on the deployment, we wouldn't have to pods running at the same time.

## Deployment with PVC

```bash
$ ./12_deployment_without_pvc.sh 
deployment.apps "busybox" deleted
persistentvolumeclaim "busybox-storage" deleted
persistentvolumeclaim/busybox-storage created
deployment.apps/busybox created
```
!!! even when I am using RWO I can start man pods, and all can mount the PV !!!