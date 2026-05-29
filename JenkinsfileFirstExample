pipeline{
    agent any

    // environment{}
    // paramters{}
    options{
        timestamps()
        timeout(time: 5, unit: 'MINUTES')
    }
    stages{
        stage("make directory"){
            options{
                retry(2)
            }
            steps{
                sh """
                    if [ ! -d ~/jenkins-pipeline-example ]; then
                        mkdir ~/jenkins-pipeline-example
                        else
                            echo "not built/already exists"
                    fi
                """
            }
        }
        stage("adding a file"){
            steps{
                sh "touch ~/jenkins-pipeline-example/file1.txt"
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: '~/jenkins-pipeline-example/*.txt', allowEmptyArchive: true
        }
    }
}
