// pipeline{
//   agent any
//   environment{
//     DOCKERHUB_CREDENTIALS = credentials('dockerhub')
//   }
// }
// USE with:

//   stage("Push to Dockerhub") {
//             steps {
//                 sh """
//                     echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin


pipeline {
    agent any

    parameters {
        booleanParam(
            name: 'USE_SLIM_IMAGE',
            defaultValue: false,
            description: "[CAUTION] - this uses experimental slim-build for RC"
        )
    }

    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub')
        IMAGE_TAG = "${BUILD_NUMBER}"
        ORIGINAL_IMAGE = "flask-app:${BUILD_NUMBER}-original"
        SLIM_IMAGE = "flask-app:${BUILD_NUMBER}-slim"
        NGINX_IMAGE = "mynginx:${BUILD_NUMBER}"
        DOCKERHUB_REPO = "chrisreeves1/flask-app"

    }

    stages {

        stage("Init") {
            steps {
                sh """
                    docker rm -f flask-app mynginx 2>/dev/null || true
                    docker network rm new-network 2>/dev/null || true
                    docker network create new-network
                """
            }
        }

        stage("Parallel pre-build checks") {
            parallel {

                stage("Initial filesystem scan") {
                    steps {
                        sh """
                            trivy fs --cache-dir /tmp/trivycache-fs --format json -o trivy-report.json .
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                        }
                    }
                }

                stage("Run unit tests") {
                    steps {
                        script {
                            catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                                sh """
                                    python3 -m venv .venv
                                    . .venv/bin/activate
                                    pip install -r requirements.txt
                                    python3 -m unittest -v test_app.py
                                    deactivate
                                """
                            }
                        }
                    }
                }

        //         stage("SonarQube Scan") {
        //             steps {
        //                 withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
        //                     sh """
        //                         rm -rf .trivycache-* .trivycache-image .trivycache-fs || true
        //                         docker run --rm \
        //                         -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
        //                         -e SONAR_TOKEN="${SONAR_TOKEN}" \
        //                         -v "${WORKSPACE}:/usr/src" \
        //                         sonarsource/sonar-scanner-cli \
        //                         -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
        //                         -Dsonar.sources=. \
        //                         -Dsonar.exclusions=.venv/**,venv/**,__pycache__/**,**/*.pyc,.trivycache*/**,**/.trivycache-image/**,**/.trivycache-fs/**
        //                     """
        //                 }
        //             }
        //         }
             }
         }

        stage("Build Metadata Collection") {
            steps {
                sh """
                    COMMIT_HASH="\$(git rev-parse HEAD 2>/dev/null || echo unknown)"
                    COMMIT_SHORT="\$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
                    BRANCH_NAME_VALUE="\$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

                    cat > build-metadata.json <<EOF
                    {
                      "commit_hash": "\${COMMIT_HASH}",
                      "commit_short": "\${COMMIT_SHORT}",
                      "branch_name": "\${BRANCH_NAME_VALUE}",
                      "build_number": "${BUILD_NUMBER}",
                      "jenkins_job": "${JOB_NAME}",
                      "build_url": "${BUILD_URL}",
                      "original_image": "${ORIGINAL_IMAGE}",
                      "slim_image": "${SLIM_IMAGE}",
                      "nginx_image": "${NGINX_IMAGE}",
                      "dockerhub_repo": "${DOCKERHUB_REPO}",
                      "sonarqube_project_key": "${SONAR_PROJECT_KEY}"
                    }
                    EOF

                    cat build-metadata.json
                """
            }

            post {
                always {
                    archiveArtifacts artifacts: 'build-metadata.json', allowEmptyArchive: true
                }
            }
        }

        stage("Build images in parallel") {
            parallel {

                stage("Build flask-app image") {
                    steps {
                        sh """
                            docker build -t ${ORIGINAL_IMAGE} .
                        """
                    }
                }

                stage("Build nginx image") {
                    steps {
                        sh """
                            docker build -t ${NGINX_IMAGE} -f Dockerfile.nginx .
                        """
                    }
                }
            }
        }

        stage("Conditional slim-image") {
            when {
                expression { return params.USE_SLIM_IMAGE }
            }

            steps {
                sh """
                    slim build \
                    --target ${ORIGINAL_IMAGE} \
                    --tag ${SLIM_IMAGE} \
                    --http-probe=false
                """
            }
        }

        stage("Select Final Image") {
            steps {
                script {
                    if (params.USE_SLIM_IMAGE) {
                        env.FINAL_IMAGE = env.SLIM_IMAGE
                    } else {
                        env.FINAL_IMAGE = env.ORIGINAL_IMAGE
                    }
                }
            }
        }

        stage("Parallel post-build actions") {
            parallel {

                stage("Image metadata") {
                    steps {
                        sh """
                            docker inspect ${FINAL_IMAGE} > docker_inspect.json
                            docker history ${FINAL_IMAGE} > docker_history.txt
                            docker images ${FINAL_IMAGE} > docker_image_size.txt
                        """
                    }

                    post {
                        always {
                            archiveArtifacts artifacts: 'docker_inspect.json,docker_history.txt,docker_image_size.txt', allowEmptyArchive: true
                        }
                    }
                }

                stage("Security scan") {
                    steps {
                        sh """
                            trivy image --cache-dir /tmp/trivycache-image --format json -o trivy-image-report.json ${FINAL_IMAGE}
                        """
                    }

                    post {
                        always {
                            archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
                        }
                    }
                }

                stage("Generate SBOM") {
                    steps {
                        sh """
                            trivy image \
                            --cache-dir /tmp/trivycache-sbom \
                            --format cyclonedx \
                            --output flask-app-sbom.cdx.json \
                            ${FINAL_IMAGE}
                        """
                    }

                    post {
                        always {
                            archiveArtifacts artifacts: 'flask-app-sbom.cdx.json', allowEmptyArchive: true
                        }
                    }
                }
            }
        }

        stage("Image Size Gate") {
            steps {
                script {
                    def sizeBytes = sh(
                        script: "docker image inspect ${FINAL_IMAGE} --format='{{.Size}}'",
                        returnStdout: true
                    ).trim().toLong()

                    def maxBytes = 200 * 1024 * 1024

                    if (sizeBytes > maxBytes) {
                        unstable("Image size threshold breached 200MB")
                    }
                }
            }
        }

        stage("Quality gate approval") {
            steps {
                input message: "Quality gate pass?", ok: "Proceed"
            }
        }

        stage("Run locally") {
            steps {
                sh """
                    docker rm -f flask-app mynginx 2>/dev/null || true

                    docker run -d \
                        --name flask-app \
                        --network new-network \
                        ${FINAL_IMAGE}

                    docker run -d \
                        --name mynginx \
                        --network new-network \
                        -p 80:80 \
                        ${NGINX_IMAGE}
                """
            }
        }

        stage("Smoke Test") {
            steps {
                sh """
                    echo "Waiting for application health endpoint..."

                    for i in 1 2 3 4 5 6 7 8 9 10; do
                        if curl -fsS http://localhost/health > /dev/null; then
                            echo "Smoke test passed."
                            exit 0
                        fi

                        sleep 3
                    done

                    echo "Smoke test failed."

                    docker logs flask-app || true
                    docker logs mynginx || true

                    exit 1
                """
            }
        }

        stage("Push to Dockerhub") {
            steps {
                sh """
                    echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin

                    docker tag ${FINAL_IMAGE} ${DOCKERHUB_REPO}:${IMAGE_TAG}
                    docker tag ${FINAL_IMAGE} ${DOCKERHUB_REPO}:latest

                    docker push ${DOCKERHUB_REPO}:${IMAGE_TAG}
                    docker push ${DOCKERHUB_REPO}:latest
                """
            }
        }
    }

    post {

        success {
            echo "completed successfully"
        }

        failure {
            echo "pipeline failed"
        }

        always {
            sh """
                docker rm -f flask-app mynginx 2>/dev/null || true
                docker network rm new-network 2>/dev/null || true
            """
        }
    }
}
