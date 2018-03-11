import sys, os, pwd, signal, time, shutil
from subprocess import *
from resource_management import *

class DemoControl(Script):
  def install(self, env):
    self.configure(env)
    import params
    
    if not os.path.exists(params.install_dir): 
        os.makedirs(params.install_dir)
    os.chdir(params.install_dir)
    Execute(params.install_dir + '/CloudBreakArtifacts/recipes/market-basket-post-install.sh')

  def start(self, env):
    self.configure(env)
    import params
    Execute( "touch /tmp/market_master.pid" )	 

  def stop(self, env):
    self.configure(env)
    import params
    Execute( "rm -f /tmp/market_master.pid" ) 

  def status(self, env):
    import params
    env.set_params(params)
    market_master_pid_file="/tmp/market_master.pid"
    Execute( format("cat {market_master_pid_file}") )


  def configure(self, env):
    import params
    env.set_params(params)

if __name__ == "__main__":
  DemoControl().execute()
