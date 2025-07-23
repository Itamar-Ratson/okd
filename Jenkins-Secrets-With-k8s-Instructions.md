# Jenkins Kubernetes Credentials Provider

Simple setup for managing Jenkins credentials using Kubernetes secrets and the Kubernetes Credentials Provider Plugin.

## Prerequisites

```bash
export KUBECONFIG=~/github/projects/okd-4/okd-install/auth/kubeconfig
oc project jenkins
```

## Setup

### 1. Configure Jenkins with JCasC

Save as `jenkins-casc-configmap.yaml`:

```yaml
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
```

### 2. Create Secrets with Labels

```bash
# API key secret
oc create secret generic api-credentials \
  --from-literal=text=your-api-key-value
oc label secret api-credentials jenkins.io/credentials-type=secretText

# Username/password secret (optional)
oc create secret generic git-credentials \
  --from-literal=username=your-username \
  --from-literal=password=your-token
oc label secret git-credentials jenkins.io/credentials-type=usernamePassword
```

### 3. Apply Configuration

```bash
oc apply -f jenkins-casc-configmap.yaml
```

## Pipeline Usage

```groovy
pipeline {
    agent any
    stages {
        stage('Use Secrets') {
            steps {
                withCredentials([
                    string(credentialsId: 'api-credentials', variable: 'API_KEY')
                ]) {
                    sh 'curl -H "Authorization: Bearer $API_KEY" https://api.example.com'
                }
            }
        }
    }
}
```

## Verification

```bash
# Check plugin loaded
oc logs dc/jenkins | grep -i "kubernetes-credentials"

# List available credentials in Jenkins UI:
# Manage Jenkins → Manage Credentials → Global
```

## Notes

- Plugin automatically discovers secrets with `jenkins.io/credentials-type` labels
- Secret names become credential IDs in Jenkins
- No Jenkins restart needed for new secrets
- Replace `your-api-key-value` with actual values
