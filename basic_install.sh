#!/usr/bin/env bash

#source0: https://github.com/usersk7/installation-kubernetes
#source1: https://linuxparrot.com/kube-shellscript-install/

# pre-requisites for k8s0 (master)
## set hostname
hostnamectl set-hostname k8s0.example.tld

## install utilities
yum -y install epel-release
yum -y install rpmconf bash-completion fail2ban-systemd iptables-services; 

## remove firewalld (interfeers with routing for now)
yum -y remove firewalld

## configure fail2ban
cat << EOF > /etc/fail2ban/jail.d/sshd.conf
[sshd]
enabled = True
action = iptables-ipset-proto4

EOF

## enable and start fail2ban
systemctl enable fail2ban
systemctl start fail2ban

## configure firewalld
## add private network connection
nmcli con add con-name my-eth1 ifname eth1 type ethernet ip4 10.1.2.1/24 autoconnect true zone trusted

## add hosts entries and be sure to specify your own ip's
cat << EOF >> /etc/hosts

# my k8s
192.168.56.1  k8s0.vagrantbox.in k8s0
192.168.56.2  k8s1.vagrantbox.in k8s1
192.168.56.3  k8s2.vagrantbox.in k8s2

EOF

## install docker container engine
yum -y install docker

## enable docker and start it
systemctl enable docker 
systemctl start docker

## enable bridge-nf-call-iptables for ipv4 and ipv6
cat << EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1

EOF
sysctl --system

# disable SELinux (sadly enough, until support is added)
setenforce 0


# install kubeadm
## add repo
cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*

EOF

## install kubelet, kubeadm and kubectl
yum install -y --disableexcludes=kubernetes kubelet kubeadm kubectl

## enable and start kubelet
systemctl enable kubelet
systemctl start kubelet

## enable bash completion for both
kubeadm completion bash > /etc/bash_completion.d/kubeadm
kubectl completion bash > /etc/bash_completion.d/kubectl

## activate the completion
. /etc/profile


# initialize cluster
kubeadm init --apiserver-advertise-address=10.1.2.1 --pod-network-cidr=10.244.0.0/16

# copy the credentials to your user
mkdir -p $HOME/.kube
cat /etc/kubernetes/admin.conf > $HOME/.kube/config
chmod 600 $HOME/.kube/config

# install networking
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml

# let master node be used as regular node (put pods there) (optional)
kubectl taint nodes --all node-role.kubernetes.io/master-