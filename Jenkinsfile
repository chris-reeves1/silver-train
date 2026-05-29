pipeline{
  agent any
  environment{
    DOCKERHUB_CREDENTIALS = credentials('dockerhub')
  }
}
USE with:

  stage("Push to Dockerhub") {
            steps {
                sh """
                    echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin
