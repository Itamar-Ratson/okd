## Deploying Jenkins with JCasC

### Jenkins with Persistent Storage and Configuration as Code

Jenkins operator is deprecated in OKD, so use built-in templates instead:

**1. Deploy Jenkins using OKD template:**
```bash
# Set kubeconfig for OKD
export KUBECONFIG=~/github/projects/okd-4/okd-install/auth/kubeconfig

# Create project and deploy Jenkins
oc new-project jenkins
oc new-app jenkins-persistent \
  --param JENKINS_IMAGE_STREAM_TAG=jenkins:2 \
  --param VOLUME_CAPACITY=10Gi \
  --param MEMORY_LIMIT=2Gi
```

**2. Create JCasC ConfigMap (`jenkins-casc-configmap.yaml`):**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-casc
  namespace: jenkins
data:
  jenkins.yaml: |
    jenkins:
      systemMessage: "Jenkins configured with JCasC"
      numExecutors: 2
    tool:
      git:
        installations:
        - name: Default
          home: git
```

**3. Mount JCasC configuration:**
```bash
oc apply -f jenkins-casc-configmap.yaml
oc set volume dc/jenkins --add --name=casc --mount-path=/var/jenkins_home/casc_configs --source='{"configMap":{"name":"jenkins-casc"}}'
oc set env dc/jenkins CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/jenkins.yaml
```

**4. Access Jenkins:**
```bash
# Get Jenkins URL
oc get route jenkins

# Get admin password
oc extract secret/jenkins --keys=password --to=-
```

**To redeploy Jenkins (if UI changes break it):**
```bash
oc delete project jenkins
# Wait for cleanup, then repeat steps 1-3
```

### Jenkins Access Information
- URL: `https://jenkins-jenkins.apps.okd.itamarratson.com`
- Username: `admin`
- Password: From `oc extract secret/jenkins --keys=password --to=-`
- Configuration: Managed via JCasC ConfigMap (avoid UI changes)

## Notes

- This creates a true single-node cluster where control plane and worker functions run on the same node
- Suitable for development, testing, and small workloads
- For production, consider multi-node setup with separate control plane and workers
- Keep installation files (`okd-install/` directory) - required for cluster destruction
- Jenkins uses OKD templates since Jenkins Operator is deprecated
- Always update Jenkins config via ConfigMap, not UI, to maintain JCasC
