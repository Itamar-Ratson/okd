# Jenkins API Credentials with JCasC

Simple setup for managing API credentials in Jenkins using Kubernetes Secrets and Configuration as Code.

## Prerequisites

- OKD cluster running with Jenkins deployed
- kubectl/oc configured for jenkins namespace

```bash
export KUBECONFIG=~/github/projects/okd-4/okd-install/auth/kubeconfig
oc project jenkins
```

## Setup

### 1. Create API Credentials Secret

```bash
oc create secret generic api-credentials \
  --from-literal=api-key=your-api-key \
  --from-literal=webhook-secret=your-webhook-secret
```

### 2. Mount Secret as Environment Variables

```bash
oc set env dc/jenkins --from=secret/api-credentials --prefix=API_
```

### 3. Create JCasC ConfigMap

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
      systemMessage: "Jenkins configured with JCasC and Secrets"
      numExecutors: 2
      
    credentials:
      system:
        domainCredentials:
        - credentials:
          - string:
              scope: GLOBAL
              id: api-key
              secret: ${API_API_KEY}
              description: "API key from secret"
              
    tool:
      git:
        installations:
        - name: Default
          home: git
```

### 4. Apply Configuration

```bash
oc apply -f jenkins-casc-configmap.yaml
```

## Verification

```bash
# Check environment variables
oc rsh dc/jenkins env | grep API_

# Verify Jenkins credentials
oc logs dc/jenkins | grep -i casc
```

## Usage in Jenkins

The API key is available as credential ID `api-key` in Jenkins pipelines:

```groovy
pipeline {
    agent any
    stages {
        stage('Use API') {
            steps {
                withCredentials([string(credentialsId: 'api-key', variable: 'API_KEY')]) {
                    sh 'curl -H "Authorization: Bearer $API_KEY" https://api.example.com'
                }
            }
        }
    }
}
```

## Notes

- Replace `your-api-key` with actual values before running
- Environment variables use `API_` prefix: `API_API_KEY`, `API_WEBHOOK_SECRET`
- Jenkins restarts automatically when ConfigMap changes
- Secrets are stored securely in etcd, not in ConfigMap
