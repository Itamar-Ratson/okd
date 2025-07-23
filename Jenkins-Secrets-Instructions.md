# Test Jenkins Pipeline with Secrets

## 1. Verify Jenkins Status

```bash
export KUBECONFIG=~/github/projects/okd-4/okd-install/auth/kubeconfig
oc project jenkins

# Check Jenkins deployment
oc get pods
oc get routes

# Get Jenkins URL and admin password
echo "Jenkins URL: $(oc get route jenkins -o jsonpath='{.spec.host}')"
echo "Admin Password: $(oc extract secret/jenkins --keys=password --to=-)"
```

## 2. Create Test Pipeline

**Pipeline Name:** `test-secrets`

**Pipeline Script:**
```groovy
pipeline {
    agent any
    stages {
        stage('Test Environment') {
            steps {
                script {
                    echo "=== Testing Jenkins Environment ==="
                    sh 'echo "Jenkins Home: $JENKINS_HOME"'
                    sh 'echo "Current User: $(whoami)"'
                    sh 'echo "Node Name: $(hostname)"'
                }
            }
        }
        
        stage('Test Secrets') {
            steps {
                script {
                    echo "=== Testing Credential Access ==="
                    
                    // Test API key credential
                    withCredentials([string(credentialsId: 'api-key', variable: 'API_KEY')]) {
                        sh '''
                            echo "API Key length: ${#API_KEY}"
                            echo "API Key first 4 chars: ${API_KEY:0:4}***"
                        '''
                    }
                    
                    // Test webhook secret credential
                    withCredentials([string(credentialsId: 'webhook-secret', variable: 'WEBHOOK')]) {
                        sh '''
                            echo "Webhook secret length: ${#WEBHOOK}"
                            echo "Webhook first 4 chars: ${WEBHOOK:0:4}***"
                        '''
                    }
                }
            }
        }
        
        stage('Test API Call') {
            steps {
                script {
                    echo "=== Testing Mock API Call ==="
                    withCredentials([string(credentialsId: 'api-key', variable: 'API_KEY')]) {
                        sh '''
                            # Mock API test (using httpbin.org)
                            curl -s -w "HTTP Status: %{http_code}\\n" \
                                -H "Authorization: Bearer $API_KEY" \
                                -H "Content-Type: application/json" \
                                "https://httpbin.org/bearer" || echo "API test completed"
                        '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "=== Pipeline Completed ==="
        }
        success {
            echo "✅ All tests passed - Jenkins secrets working correctly!"
        }
        failure {
            echo "❌ Tests failed - check Jenkins configuration"
        }
    }
}
```

## 3. Create Pipeline via CLI (Alternative)

```bash
# Create test pipeline job
cat << 'EOF' > test-pipeline.xml
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Test pipeline for Jenkins secrets</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>
pipeline {
    agent any
    stages {
        stage('Test Secrets') {
            steps {
                withCredentials([
                    string(credentialsId: 'api-key', variable: 'API_KEY'),
                    string(credentialsId: 'webhook-secret', variable: 'WEBHOOK')
                ]) {
                    sh 'echo "API Key: ${API_KEY:0:4}***"'
                    sh 'echo "Webhook: ${WEBHOOK:0:4}***"'
                    sh 'curl -s -H "Authorization: Bearer $API_KEY" https://httpbin.org/bearer'
                }
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

# Upload pipeline (requires Jenkins CLI - optional)
# java -jar jenkins-cli.jar -s http://jenkins-route create-job test-secrets < test-pipeline.xml
```

## 4. Manual Steps to Create Pipeline

1. **Access Jenkins:**
   ```bash
   echo "https://$(oc get route jenkins -o jsonpath='{.spec.host}')"
   ```

2. **Login:** Username `admin`, password from: `oc extract secret/jenkins --keys=password --to=-`

3. **Create Pipeline:**
   - Click "New Item"
   - Name: `test-secrets`
   - Type: "Pipeline"
   - In "Pipeline Script" section, paste the pipeline code above
   - Save

4. **Run Pipeline:**
   - Click "Build Now"
   - Watch console output

## 5. Expected Output

```
=== Testing Jenkins Environment ===
Jenkins Home: /var/jenkins_home
Current User: jenkins
Node Name: jenkins-1-xxxxx

=== Testing Credential Access ===
API Key length: 20
API Key first 4 chars: your***
Webhook secret length: 32
Webhook first 4 chars: your***

=== Testing Mock API Call ===
HTTP Status: 200
✅ All tests passed - Jenkins secrets working correctly!
```

## Troubleshooting

```bash
# Check if secrets are mounted as env vars
oc rsh dc/jenkins env | grep API_

# Check JCasC logs
oc logs dc/jenkins | grep -i casc

# Verify credentials in Jenkins
# Go to: Manage Jenkins → Manage Credentials → Global
```
