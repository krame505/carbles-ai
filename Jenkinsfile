#!groovy

library "github.com/melt-umn/jenkins-lib"

// This isn't a real extension, so we use a semi-custom approach

melt.setProperties(silverBase: true, ablecBase: true)

def extension_name = 'carbles-ai'

melt.trynode(extension_name) {
  def newenv

  stage ("Checkout") {
    // We'll check it out underneath extensions/ just so we can re-use this code
    // It shouldn't hurt because newenv should specify where extensions and ablec_base can be found
    newenv = ablec.prepareWorkspace(extension_name)
  }

  stage ("Build") {
    withEnv(newenv) {
      dir("extensions/carbles-ai") {
        sh "make -j"
      }
    }
  }

  stage ("Test") {
    withEnv(newenv) {
      dir("extensions/carbles-ai") {
        sh "./bin/rel/play random heuristic random rule"
        sh './bin/rel/serve & serve_pid=$!; /export/scratch/jenkins/python-venv/bin/python test-server.py localhost:8000 30; kill $serve_pid'
      }
    }
  }

  /* If we've gotten all this way with a successful build, don't take up disk space */
  sh "rm -rf generated/* || true"
}
