#!/usr/bin/env python
from resource_management import *

# server configurations
config = Script.get_config()

#download_url = config['configurations']['control-config']['marketbasket.download_url']
install_dir = config['configurations']['control-config']['democontrol.install_dir']
