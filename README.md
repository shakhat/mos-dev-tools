fuel-tools
==========

**Turn Fuel master into powerful devbox!**

Installation
------------
# Login into Fuel master node
# yum install git
# git clone https://github.com/shakhat/mos-dev-tools.git
# cd fuel-tools
# ./install.sh
# ./rejoin.sh

Tools
-----
* **tempest** - runs Tempest tests, e.g. `tempest -- tempest.network.test_ports`
* **rally** - runs Rally suite, e.g. `rally/doc/samples/tasks/scenarios/neutron/create_and_list_networks.yaml`

Configs
-------
* **helpers/shouldfail** - list tests that due to architecture specific are expected to fail in MOS
