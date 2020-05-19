# Custom Metrics API

The custom metrics API allows the HPA v2 to scale based on arbirary metrics.

### Sample App

Additionally, this directory contains a sample app that uses the [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) to scale the Deployment's replicas of Pods up and down as needed.  

- Deploy this app, ServiceMonitor, HPA together by running `kubectl apply -f sample-app.yaml`. 

- Verify you can get custom metric via command like below:
```
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests" | jq .
```

- Next you need to put some load on its http endpoints. 

A tool like [hey](https://github.com/rakyll/hey) is helpful for doing so: 
```shell
kubectl run --rm utils -it --generator=run-pod/v1 --image arunvelsriram/utils bash
wget https://storage.googleapis.com/hey-release/hey_linux_amd64
mv hey_linux_amd64 hey && chmod +x hey
./hey -c 20 -n 100000000 http://sample-app.default.svc:8080/metrics
```

- Observe the replica changes of the sample deployment:
```
kubectl get deploy sample-app --watch
```

- Stop the load generation tool `hey` by `ctl + c` and then observe the replica changes of the sample deployment:
```
kubectl get deploy sample-app --watch
```

- You can get resource metrics like cpu/memory of node or pod via command like below (Same as kubectl top nodes/pods):
```
## get node metrics
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes/i-2dazc1d6" | jq .

### get pod metrics
kubectl get --raw  "/apis/metrics.k8s.io/v1beta1/namespaces/default/pods" | jq .
kubectl get --raw  "/apis/metrics.k8s.io/v1beta1/namespaces/kube-system/pods/kube-controller-manager-i-ezjb7gsk" | jq .
```
