mos-dev-tools
=============

**Ultimate set of tools for MOS developers and testers**

Installation
------------
1. Login into Fuel master node
1. `yum install git`
1. `git clone https://github.com/shakhat/mos-dev-tools.git`
1. `cd mos-dev-tools`
1. `./install.sh`
1. `./rejoin.sh`

Tools
-----
* **tempest** - runs Tempest tests, e.g. `tempest -- tempest.network.test_ports`
* **rally** - runs Rally suite, e.g. `rally/doc/samples/tasks/scenarios/neutron/create_and_list_networks.yaml`

Configs
-------
* **helpers/shouldfail** - list tests that due to architecture specific are expected to fail in MOS
