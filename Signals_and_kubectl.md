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
$ oc get pod -o wide
NAME                                        READY   STATUS    RESTARTS   AGE     IP            NODE        NOMINATED NODE   READINESS GATES
busybox                                     1/1     Running   0          8s      10.128.2.49   compute-2   <none>           <none>
```
You can also set a nodeSelector to specify the node.

## kubectl delete pod
Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
14:55:28
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template '{{.info.pid}}' `crictl ps|grep busybox | cut -f 1 -d ' '`) --absolute-timestamps
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

## kubectl delete pod --grace-period=1
Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
15:16:48
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template '{{.info.pid}}' `crictl ps|grep busybox | cut -f 1 -d ' '`) --absolute-timestamps
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
Terminal 1: Start a simple busybox pod that just sleeps forever.
```bash
$ date -u +%R:%S && kubectl run --image=busybox busybox sleep infinity
15:29:00
pod/busybox created
```

Terminal 2:
```bash
# strace -p $(crictl inspect --output go-template --template '{{.info.pid}}' `crictl ps|grep busybox | cut -f 1 -d ' '`) --absolute-timestamps
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

Only the pod is removed, but the process does not receive a SIGKILL before the graceperiod ends. (attantion terminationGracePeriodSeconds). You are not able to send a second kubctl delete pod.

## crictl stop

The only way to realy kill a pod is currecntly **crictl stop **.

You have to open another terminal on the node and

```bash
# date -u +%R:%S && crictl stop (crictl inspect --output go-template --template '{{.info.pid}}' `crictl ps|grep busybox | cut -f 1 -d ' '`) --absolute-timestamps`
16:00:17
ea5a7305e8d88
```

```
16:00:17 +++ killed by SIGKILL +++
```

This command send directly a SIGKILL.

## Summery

A Pod kill works only with **--grace-period=1** (nearly one secound delay).

An Kubernetes issue was opened almost two years ago pointing out that behavior. But in the meantime it is autoclosed. :-( 
https://github.com/kubernetes/kubernetes/issues/86914