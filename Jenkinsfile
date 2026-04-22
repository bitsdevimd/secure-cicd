pipeline {
  agent any

  environment {
    REGISTRY      = 'localhost:5000'
    IMAGE_NAME    = 'secure-app'
    IMAGE_TAG     = "${BUILD_NUMBER}-${GIT_COMMIT[0..6]}"
    FULL_IMAGE    = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    SONAR_TOKEN   = credentials('sonarqube-token')
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_AUTHOR = sh(returnStdout: true,
            script: 'git log -1 --format="%an"').trim()
        }
        echo "Branch: ${GIT_BRANCH} | Commit: ${GIT_COMMIT[0..6]}"
      }
    }

    stage('Static Code Analysis') {
      steps {
        withSonarQubeEnv('SonarQube') {
          sh '''
            sonar-scanner \
              -Dsonar.projectKey=secure-app \
              -Dsonar.sources=. \
              -Dsonar.host.url=http://host.docker.internal:9000 \
              -Dsonar.login=${SONAR_TOKEN}
          '''
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Secret Detection') {
      steps {
        sh '''
          docker run --rm \
            -v ${WORKSPACE}:/path \
            zricethezav/gitleaks:latest \
            detect --source /path \
            --report-format sarif \
            --report-path /path/gitleaks-report.sarif \
            --exit-code 1
        '''
      }
      post { always { archiveArtifacts artifacts: 'gitleaks-report.sarif',
                      allowEmptyArchive: true } }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          docker build \
            --no-cache \
            -t ${FULL_IMAGE} \
            -f Dockerfile .
        '''
      }
    }

    stage('Image Vulnerability Scan') {
      steps {
        sh '''
          trivy image \
            --exit-code 1 \
            --severity CRITICAL,HIGH \
            --format table \
            --output trivy-report.txt \
            ${FULL_IMAGE}
        '''
      }
      post { always { archiveArtifacts artifacts: 'trivy-report.txt',
                      allowEmptyArchive: true } }
    }

    stage('Policy-as-Code Validation') {
      steps {
        sh '''
          kyverno apply k8s/policies/ --resource k8s/manifests/ \
            --detailed-results 2>&1 | tee kyverno-report.txt
          if grep -q "FAIL" kyverno-report.txt; then
            echo "Kyverno policy violations detected!"
            exit 1
          fi
          echo "All Kyverno policies passed!"
        '''
      }
      post { always { archiveArtifacts artifacts: 'kyverno-report.txt',
                      allowEmptyArchive: true } }
    }

    stage('Push to Local Registry') {
      steps {
        sh '''
          # No login needed for local registry
          docker push ${FULL_IMAGE}
          docker tag ${FULL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:latest
          docker push ${REGISTRY}/${IMAGE_NAME}:latest
        '''
      }
    }

    stage('Deploy to Minikube') {
      steps {
        withKubeConfig([credentialsId: 'kubeconfig-minikube']) {
          sh '''
            sed -i "s|IMAGE_PLACEHOLDER|${FULL_IMAGE}|g" \
              k8s/manifests/deployment.yaml
            kubectl apply -f k8s/manifests/namespace.yaml
            kubectl apply -f k8s/manifests/ --namespace=secure-app
            kubectl rollout status deployment/secure-app \
              --namespace=secure-app --timeout=120s
          '''
        }
      }
    }

    stage('Smoke Test') {
      steps {
        withKubeConfig([credentialsId: 'kubeconfig-minikube']) {
          sh '''
            POD=$(kubectl get pod -n secure-app -l app=secure-app \
              -o jsonpath='{.items[0].metadata.name}')
            kubectl exec -n secure-app $POD -- \
              wget -qO- http://localhost:8080/health
          '''
        }
      }
    }
  }

  post {
    always { cleanWs() }
  }
}
