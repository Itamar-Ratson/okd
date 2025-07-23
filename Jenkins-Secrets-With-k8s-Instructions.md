# Jenkins with Kubernetes Credentials Provider on OKD

Complete guide to set up Jenkins with the Kubernetes Credentials Provider plugin on OKD, allowing secrets to be managed via Kubernetes labels instead of Jenkins UI.

## Prerequisites

```bash
# OKD cluster running
export KUBECONFIG=~/github/projects/okd-4/okd-install/auth/kubeconfig
oc project jenkins
```

## 1. Deploy Jenkins

```bash
oc new-project jenkins
oc new-app jenkins-persistent \
  --param JENKINS_IMAGE_STREAM_TAG=jenkins:2 \
  --param VOLUME_CAPACITY=10Gi \
  --param MEMORY_LIMIT=2Gi
```

## 2. Create JCasC ConfigMap (Basic)

```bash
cat << 'EOF' > jenkins-casc-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-casc
  namespace: jenkins
data:
  jenkins.yaml: |
    jenkins:
      systemMessage: "Jenkins with K8s Credentials"
      numExecutors: 2
      
    tool:
      git:
        installations:
        - name: Default
          home: git
EOF

oc apply -f jenkins-casc-configmap.yaml
```

## 3. Mount JCasC Configuration

```bash
oc set volume dc/jenkins --add --name=casc --mount-path=/var/jenkins_home/casc_configs --source='{"configMap":{"name":"jenkins-casc"}}'
oc set env dc/jenkins CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/jenkins.yaml
```

## 4. Restart Jenkins and Wait for Ready

```bash
oc scale dc/jenkins --replicas=0
sleep 10
oc scale dc/jenkins --replicas=1

# Wait for pod to be Ready
oc get pods -w
# Wait for 1/1 Ready, then Ctrl+C
```

## 5. Install Kubernetes Credentials Provider Plugin

```bash
# Download compatible version (0.15 works with Jenkins 2.426.3)
oc rsh dc/jenkins curl -L https://updates.jenkins.io/download/plugins/kubernetes-credentials-provider/0.15/kubernetes-credentials-provider.hpi -o /var/lib/jenkins/plugins/kubernetes-credentials-provider.jpi

# Restart Jenkins
oc scale dc/jenkins --replicas=0
sleep 10
oc scale dc/jenkins --replicas=1
```

## 6. Update JCasC with Plugin Configuration

```bash
cat << 'EOF' > jenkins-casc-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-casc
  namespace: jenkins
data:
  jenkins.yaml: |
    jenkins:
      systemMessage: "Jenkins with K8s Credentials Provider"
      numExecutors: 2
      
    unclassified:
      kubernetes-credentials-provider:
        enabled: true
        
    tool:
      git:
        installations:
        - name: Default
          home: git
EOF

oc apply -f jenkins-casc-configmap.yaml
oc scale dc/jenkins --replicas=0
sleep 10
oc scale dc/jenkins --replicas=1
```

## 7. Create Labeled Secrets

```bash
# Test secret
oc create secret generic test-secret \
  --from-literal=text=hello-world
oc label secret test-secret jenkins.io/credentials-type=secretText

# API credentials
oc create secret generic api-key \
  --from-literal=text=your-api-key-value
oc label secret api-key jenkins.io/credentials-type=secretText

# Username/password credentials
oc create secret generic git-creds \
  --from-literal=username=your-username \
  --from-literal=password=your-token
oc label secret git-creds jenkins.io/credentials-type=usernamePassword
```

## 8. Verify Setup

```bash
# Check Jenkins is running
oc get pods

# Get access info
echo "URL: https://$(oc get route jenkins -o jsonpath='{.spec.host}')"
echo "User: admin"
echo "Password: $(oc extract secret/jenkins --keys=password --to=-)"

# Check plugin loaded
oc logs dc/jenkins | grep "kubernetes_credentials_provider"
```

## 9. Test Pipeline

Create a pipeline in Jenkins UI with this script:

```groovy
pipeline {
    agent any
    stages {
        stage('Test K8s Credentials') {
            steps {
                withCredentials([
                    string(credentialsId: 'test-secret', variable: 'TEST_VAL'),
                    string(credentialsId: 'api-key', variable: 'API_KEY')
                ]) {
                    sh '''
                        echo "Test Secret: $TEST_VAL"
                        echo "API Key length: ${#API_KEY}"
                        echo "✅ Kubernetes Credentials Provider working!"
                    '''
                }
            }
        }
    }
}
```

## Verification Checklist

- [ ] Jenkins pod is 1/1 Ready
- [ ] Plugin appears in **Manage Jenkins** → **Manage Plugins** → **Installed**
- [ ] Secrets appear in **Manage Jenkins** → **Manage Credentials** → **Global**
- [ ] Pipeline can access secrets via `credentialsId`

## Important Notes

- Secret names become credential IDs in Jenkins
- Plugin automatically discovers secrets with `jenkins.io/credentials-type` labels
- Supported types: `secretText`, `usernamePassword`
- No restart needed when adding new labeled secrets
- Plugin version 0.15 compatible with Jenkins 2.426.3 in OKD

## Troubleshooting

```bash
# Check plugin files
oc rsh dc/jenkins ls -la /var/lib/jenkins/plugins/ | grep kubernetes

# Check JCasC logs
oc logs dc/jenkins | grep -i casc

# Check plugin errors
oc logs dc/jenkins | grep -i "kubernetes-credentials"

# List labeled secrets
oc get secrets -l jenkins.io/credentials-type
```

## File Structure

```
jenkins-casc-configmap.yaml    # JCasC configuration
```

Keep this file for redeployment.
