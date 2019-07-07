# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/bionic64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 2
  end
  config.vm.provision "shell", inline: <<-SHELL
    apt-get update

    apt-get install apt-transport-https ca-certificates curl software-properties-common jq
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce

    apt-get install -y cgdb
    apt-get install -y cgroup-tools

    apt-get install -y make gcc
    git clone git://git.kernel.org/pub/scm/linux/kernel/git/morgan/libcap.git /usr/src/libcap
    (cd /usr/src/libcap && make && make install)
  SHELL
end
