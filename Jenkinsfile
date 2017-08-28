node {
  checkout scm
  stage('Style checks') {
    sh(
      script: '''
      source /var/lib/jenkins/.bash_profile

      # Checking json syntax
      for file in $(find . -type f -name "*.json");do
        jsonlint ${file};
      done

      # Checking ruby syntax and styles
      cookstyle .

      # Checking chef syntax and styles
      foodcritic .
      '''
    )
  }
  stage('Integration tests') {
    sh(
      script: '''
      source /var/lib/jenkins/.bash_profile
      ./chefci.sh
      '''
    )
  }
  cleanWs()
}
