# PoCs

This folder is dedicated to hosting various PoCs for testing and demonstrating
potential configurations or enhancements in the Metal3 environment.

## PoCs Overview

### 1. PoC Hostnetworkless Ironic with VirtualMedia Using NodePorts

This PoC is part of the discussion [metal3-io/baremetal-operator#1739](https://github.com/metal3-io/baremetal-operator/discussions/1739)
and demonstrates running Ironic without `hostNetwork`, limited to the VirtualMedia
use case, using a NodePort service.

**Branch:**

Run this PoC or review code changes at [hostnetworkless-ironic-
nodeport](https://github.com/Nordix/metal3-dev-env/tree/test-svc-nodePort/mboukhalfa)

**Key Changes:**

1. **Edit Ironic Deployment:**

   - Remove `hostNetwork: true`.
   - Remove `dnsmasq` container.
   - Remove security restrictions to allow root access for debugging inside
   the containers.

1. **Add NodePort Service:**

   - Map the following ports:

   ```pseudocode
   - ironic
     30085:6385
   - inspector
     30050:5050
   - httpd
     30080:30080
   ```

   - Changed the `httpd` internal port because the `HTTP_PORT` variable is used
   in both internal and external configurations.

1. **Edit Ironic ConfigMap:**

   - Remove `PROVISIONING_IP` so that `runironic` uses the pod's IP from the
   `eth0` interface.
   - Add external Ironic IPs to be published to external components like IPA.

1. **Provisioning Networks:**

   - Remove `keepalived` since it cannot access the `ironicendpoint` bridge; instead,
   use manual commands to configure the bridge with the Ironic external IP.
   - Manually remove the IP from minikube and add it to the CP node during pivot.

### 2. PoC Hostnetworkless Ironic with VirtualMedia Using MetalLB LoadBalancer

This PoC is part of the discussion [metal3-io/baremetal-operator#1739](https://github.com/metal3-io/baremetal-operator/discussions/1739)
and demonstrates running Ironic without`hostNetwork`, limited to the
VirtualMedia use case, using a MetalLB LoadBalancer service.

**Branch:**

Run this PoC or review code changes at [hostnetworkless-ironic-metallb](https://github.com/Nordix/metal3-dev-env/tree/PoC-lb-ironic/mohammed)

**Key Changes:**

1. **Edit Ironic Deployment:**

   - Remove `hostNetwork: true`.
   - Remove `dnsmasq` container.
   - Remove `keepalived` container.
   - Remove security restrictions to allow root access for debugging inside
   the containers.

1. **Add MetalLB Service:**

   - Enable MetalLB on Minikube: `minikube addons enable metallb`
   - Install on the target cluster: `kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml`
   - Create an IP pool:

       ```yaml
       apiVersion: metallb.io/v1beta1
       kind: IPAddressPool
       metadata:
         name: ironic-pool
         namespace: metallb-system
       spec:
         addresses:
         - 172.22.0.2-172.22.0.2
       ---
       apiVersion: metallb.io/v1beta1
       kind: L2Advertisement
       metadata:
         name: ironic
         namespace: metallb-system
       spec:
         ipAddressPools:
         - ironic-pool
       ```

1. **Add LoadBalancer Service:**

  ```yaml
  apiVersion: v1
   kind: Service
   metadata:
     name: ironic
     annotations:
       metallb.universe.tf/loadBalancerIPs: 172.22.0.2
   spec:
     ports:
     - name: ironic
       port: 6385
       targetPort: 6385
     - name: inspector
       port: 5050
       targetPort: 5050
     - name: httpd
       port: 6180
       targetPort: 6180
     selector:
       name: ironic
     type: LoadBalancer
  ```

1. **Edit Ironic ConfigMap:**

   - Remove `PROVISIONING_IP` so that the `runironic` script uses the pod's
   IP from the `eth0` interface.
   - Add external Ironic IPs to be published to external components like IPA.

1. **Provisioning Networks:**

   - No need to configure the `ironicendpoint` with 172.22.0.2

### 3. PoC Hosted control-plane using Kamaji

This PoC does NOT build on metal3-dev-env. It demonstrates how Kamaji can be
used as a control-plane provider together with Metal3 as an infrastructure
provider to create workload clusters where the control-plane is hosted in the
management cluster. The control-plane components run as pods and are exposed via
a LoadBalancer Service. This is a way to save resources by not having dedicated
control-plane nodes for each workload cluster.

See the [README.md](./kamaji/README.md) in the `kamaji` directory for more
details.
