# **Service Mesh Lab: Complete Guide (Linkerd on K3s)**

## **Prerequisites**
*   **Environment:** 3-node K3s cluster (1 Control Plane, 2 Workers) running in Vagrant VMs.
*   **Resources:** ~2GB RAM per VM, 2 vCPUs per VM.
*   **Networking:** MetalLB configured to assign IPs from your private network range (e.g., `192.168.1.x`).
*   **Host Machine:** Linux/macOS/Windows with `kubectl`, `vagrant`, and a browser.
*   **Starting Point:** All 3 nodes are `Ready` in Kubernetes, and `kubectl` is configured on the Control Plane node.

---

## **Phase 1: Deploy Microservices**
*Goal: Create a simple frontend/backend architecture to test connectivity.*

### **1.1 Deploy the Backend**
Create `backend.yaml` on the Control Plane node:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: python:3.9-slim
        command:
          - python
          - -c
          - |
            import http.server, socketserver, os
            PORT = 8000
            Handler = http.server.SimpleHTTPRequestHandler
            class MyHandler(Handler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header('Content-type', 'text/plain')
                    self.end_headers()
                    self.wfile.write(f"Hello from Backend! Pod: {os.urandom(4).hex()}".encode())
            socketserver.TCPServer.allow_reuse_address = True
            with socketserver.TCPServer(("", PORT), MyHandler) as httpd:
                httpd.serve_forever()
        ports:
        - containerPort: 8000
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: backend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: LoadBalancer
```
**Apply:**
```bash
kubectl apply -f backend.yaml
```

### **1.2 Deploy the Frontend**
Create `frontend.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        startupProbe:
          httpGet:
            path: /
            port: 80
          failureThreshold: 30
          periodSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: LoadBalancer
```
**Apply:**
```bash
kubectl apply -f frontend.yaml
```

### **1.3 Verify Connectivity**
1.  Get the Frontend LoadBalancer IP:
    ```bash
    kubectl get svc frontend-service
    ```
    *(Note the `EXTERNAL-IP`, e.g., `192.168.1.55`)*
2.  Test from your host machine:
    ```bash
    curl http://<EXTERNAL-IP>
    ```
    *(Expected: Nginx welcome page)*
3.  Test internal connectivity (from a frontend pod to backend):
    ```bash
    kubectl exec -it $(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- sh
    # Inside pod:
    curl http://backend-service
    ```
    *(Expected: `Hello from Backend!`)*

---

## **Phase 2: Install Linkerd**
*Goal: Install the Service Mesh Control Plane and Dashboard.*

### **2.1 Install Linkerd CLI**
On the Control Plane node:
```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
export PATH=$PATH:$HOME/.linkerd2/bin
```

### **2.2 Install Gateway API CRDs**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

### **2.3 Install Linkerd Control Plane**
```bash
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```
*(Ensure all checks pass)*

### **2.4 Install Linkerd Viz (Dashboard)**
```bash
linkerd viz install | kubectl apply -f -
linkerd viz check
```

### **2.5 Access the Dashboard**
From your **host machine** (not the VM), run:
```bash
kubectl port-forward -n linkerd-viz svc/web 50750:8084
```
Open `http://localhost:50750` in your browser.

---

## **Phase 3: Inject the Mesh**
*Goal: Add sidecar proxies to your applications.*

### **3.1 Inject Frontend and Backend**
```bash
# Create a ServiceAccount for the frontend (for later security)
kubectl create serviceaccount frontend-sa

# Inject and apply Backend
kubectl get deployment backend -o yaml | linkerd inject - | kubectl apply -f -

# Inject and apply Frontend (patching to use frontend-sa)
kubectl get deployment frontend -o yaml | linkerd inject - | kubectl apply -f -
kubectl patch deployment frontend -p '{"spec":{"template":{"spec":{"serviceAccountName":"frontend-sa"}}}}'
```

### **3.2 Verify Injection**
```bash
kubectl get pods -o wide
```
*(Ensure `READY` column shows `2/2` for both frontend and backend)*

### **3.3 Verify Mesh Status**
```bash
linkerd viz stat -n default deployment
```
*(Expected: `MESHED: 2/2`, `SUCCESS: 100%`)*

---

## **Phase 4: Security Policies (Zero Trust)**
*Goal: Block unauthenticated traffic and allow only specific identities.*

### **4.1 Create a Server Resource**
This defines which port and pods are protected. **Note:** Target the container port (`8000`), not the service port (`80`).
```bash
kubectl apply -f - <<EOF
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: backend-server
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  port: 8000
  proxyProtocol: HTTP/1
EOF
```

### **4.2 Create an Authorization Policy**
This requires clients to have a valid mTLS certificate.
```bash
kubectl apply -f - <<EOF
apiVersion: policy.linkerd.io/v1beta1
kind: ServerAuthorization
metadata:
  name: backend-allow-all-authenticated
  namespace: default
spec:
  server:
    name: backend-server
  client:
    meshTLS:
      identities:
        - "*"
EOF
```

### **4.3 Test Security (The "Aha!" Moment)**

**Test A: Unauthenticated Access (Should FAIL)**
```bash
kubectl run test-pod --image=busybox --rm -it --restart=Never -- sh
# Inside the pod:
wget -qO- http://backend-service
```
*(Expected: `HTTP/1.1 403 Forbidden`)*

**Test B: Authenticated Access (Should SUCCEED)**
```bash
curl http://<Frontend-LoadBalancer-IP>
```
*(Expected: `Hello from Backend!`)*

### **4.4 (Optional) Restrict to Specific Identity**
To allow **only** the frontend, update the policy to use the specific identity string.
*Note: The identity format is `cluster.local/ns/<namespace>/sa/<serviceaccount>`.*

```bash
kubectl apply -f - <<EOF
apiVersion: policy.linkerd.io/v1beta1
kind: ServerAuthorization
metadata:
  name: backend-allow-frontend-only
  namespace: default
spec:
  server:
    name: backend-server
  client:
    meshTLS:
      identities:
        - "cluster.local/ns/default/sa/frontend-sa"
EOF
```
*(If the identity string causes a regex error, verify the exact identity using `kubectl logs -l app=frontend -c linkerd-proxy | grep identity`)*

---

## **Lab Completion Checklist**
- [ ] 3-node K3s cluster running with MetalLB.
- [ ] Frontend and Backend services deployed and accessible.
- [ ] Linkerd Control Plane and Viz Dashboard installed.
- [ ] Sidecar proxies injected (`2/2` ready).
- [ ] Dashboard shows traffic and mTLS enabled.
- [ ] **Security Policy:** Unauthenticated traffic is blocked (`403`), authenticated traffic is allowed.

You now have a fully functional, secure Service Mesh environment!