fuel-tools
==========

**Turn Fuel master into powerful devbox!**

Installation
------------
1. Login into Fuel master node
2. yum install git
3. git clone https://github.com/shakhat/fuel-tools.git
4. cd fuel-tools
5. ./install.sh
6. ./rejoin.sh

Tools
-----
* tempest - runs Tempest tests, e.g. **"tempest -- tempest.network.test_ports"**
* rally - runs Rally suite, e.g. **"rally/doc/samples/tasks/scenarios/neutron/create_and_list_networks.yaml"**

Development
-----------
1. Run tests: tox
