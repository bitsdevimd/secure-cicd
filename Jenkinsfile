pipeline {
    agent any

    environment {
        // ── Local registry (minikube addon) replaces AWS ECR ──────────
        REGISTRY      = 'localhost:5000'
        IMAGE_NAME    = 'secure-app'

        // ── SonarQube running as Docker container on host ──────────────
        // host.docker.internal resolves to host machine from inside Docker
        SONAR_URL     = 'http://host.docker.internal:9000'
        SONAR_TOKEN   = credentials('SonarToken')

        // ── Minikube kubeconfig credential ID ─────────────────────────
        KUBECONFIG_CRED = 'kubeconfig-minikube'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        // ─── Stage 1: Checkout ───────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_AUTHOR = sh(returnStdout: true,
                        script: 'git log -1 --format="%an"').trim()
                    env.GIT_MSG    = sh(returnStdout: true,
                        script: 'git log -1 --format="%s"').trim()
        
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    env.FULL_IMAGE = "${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
            }
        }

        // ─── Stage 2: Static Code Analysis (SonarQube) ───────────────
        stage('Static Code Analysis') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=${IMAGE_NAME} \
                              -Dsonar.sources=.
                        """
                    }
                }
            }
        }

        // ─── Stage 3: Quality Gate ────────────────────────────────────
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: false  // true flag fails the pipleine 
                }
            }
        }

        // ─── Stage 4: Secret Detection (Gitleaks via Docker) ─────────
        stage('Secret Detection') {
            steps {
                    sh """
                    docker run --rm \
                      -v ${WORKSPACE}:/path \
                      zricethezav/gitleaks:latest detect \
                      --source /path \
                      --no-git \
                      --report-format sarif \
                      --report-path /path/gitleaks-report.sarif \
                      --exit-code 1
                    """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.sarif', allowEmptyArchive: true
                }
            }
        }

        // ─── Stage 5: Build Docker Image ─────────────────────────────
        stage('Build Docker Image') {
            steps {
                script {
                    // 🔍 DEBUG: check files in workspace
                    sh 'pwd'
                    sh 'ls -l'
        
                    // 🚀 Actual build
                    sh """
                    docker build --no-cache \
                      --label git-commit=${GIT_COMMIT} \
                      -t ${FULL_IMAGE} \
                      -f Dockerfile .
                    """
                }
            }
        }

        // ─── Stage 6: Container Vulnerability Scan (Trivy) ───────────
        stage('Image Vulnerability Scan') {
            steps {
                sh """
                    # Code 1 exits if vulnerabilities found
                    # Code 0 allows pipeline to continue
                    trivy image \
                      --exit-code 0 \
                      --severity CRITICAL,HIGH \
                      --format table \
                      --output trivy-report.txt \
                      ${FULL_IMAGE}
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true
                    sh """
                        trivy image \
                          --exit-code 0 \
                          --format json \
                          --output trivy-report.json \
                          ${FULL_IMAGE} || true
                    """
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        // ─── Stage 7: Kubernetes Policy Validation (Kyverno CLI) ─────
        stage('Policy-as-Code Validation') {
            steps {
                sh """
                    kyverno apply k8s/policies/ --resource k8s/manifests/ \
                      --detailed-results \
                      2>&1 | tee kyverno-report.txt

                    if grep -q "FAIL" kyverno-report.txt; then
                        echo "Kyverno policy violations detected!"
                        cat kyverno-report.txt
                        exit 1
                    fi
                    echo "All Kyverno policies passed!"
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'kyverno-report.txt', allowEmptyArchive: true
                }
            }
        }

        // ─── Stage 8: YAML Lint ───────────────────────────────────────
        stage('YAML Lint') {
            steps {
                sh """
                    yamllint -d '{extends: default, rules: {line-length: {max: 150}}}' \
                      k8s/manifests/ k8s/policies/
                """
            }
        }

        // ─── Stage 9: Push to Local Registry (replaces ECR) ──────────
        stage('Push to Local Registry') {
            steps {
                sh """
                    # No AWS login needed — local registry has no auth
                    docker push ${FULL_IMAGE}

                    # Tag and push as latest too
                    docker tag ${FULL_IMAGE} ${REGISTRY}/${IMAGE_NAME}:latest
                    docker push ${REGISTRY}/${IMAGE_NAME}:latest

                    echo "Image pushed: ${FULL_IMAGE}"
                """
            }
        }

        // ─── Stage 10: Deploy to Minikube (replaces EKS) ─────────────
        stage('Deploy to Minikube') {
            steps {
                withKubeConfig([credentialsId: "${KUBECONFIG_CRED}"]) {
                    sh """
                        # Replace image placeholder with actual image
                        sed -i 's|IMAGE_PLACEHOLDER|${FULL_IMAGE}|g' \
                          k8s/manifests/deployment.yaml

                        # Create namespace
                        kubectl apply -f k8s/manifests/namespace.yaml

                        # Apply all manifests
                        kubectl apply -f k8s/manifests/ --namespace=secure-app

                        # Wait for rollout
                        kubectl rollout status deployment/secure-app \
                          --namespace=secure-app \
                          --timeout=120s
                    """
                }
            }
        }

        // ─── Stage 11: Smoke Test ─────────────────────────────────────
        stage('Smoke Test') {
            steps {
                withKubeConfig([credentialsId: "${KUBECONFIG_CRED}"]) {
                    sh """
                        POD=\$(kubectl get pod -n secure-app -l app=secure-app \
                          -o jsonpath='{.items[0].metadata.name}')
                        echo "Testing pod: \$POD"
                        kubectl exec -n secure-app \$POD -- \
                          wget -qO- http://localhost:8080/health || true
                    """
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline SUCCESS — Image: ${FULL_IMAGE}"
        }
        failure {
            echo "Pipeline FAILED at stage: ${STAGE_NAME}"
        }
        always {
            node('built-in') {
            cleanWs()
        }
    }
    }
}
