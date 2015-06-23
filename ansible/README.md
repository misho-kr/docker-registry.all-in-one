Docker Registry image build procedure
=====================================

[Ansible playbook](http://docs.ansible.com/playbooks.html) to build the Docker images of the registry with all customizations and options we have added to it.

## Benefits

The procedure to build Docker images of the [docker registry](https://github.com/dotcloud/docker-registry) is quite lengthy, the commands are long and it takes fair amount of copy-and-paste actions to build the images from scratch. Some build steps may fail which requires careful inspection of the commands output to catch posisble errors. All that is boring and error-prone so there should be another way to build images.

[Ansible](http://docs.ansible.com/intro.html) comes to the rescue and takes care to run all build steps in the right order, check they all complete succssfully and the final result is as expected.

## Run the playbook

Ansible has very low requirements so there should be nothing to install on the local or remote machines in order to complete the build (unless the build host has Python 2.4 but let's assume that is unlikely). Run these commands to copy the playbook from [GitHub](https://github.com/misho-kr/docker-registry.all-in-one) and execute it.

The playbook has two requirements for the build host so make sure they are satisfied:

* Docker is installed and the login user is permitted to execute it
* The login user has __sudo__ privilege

TODO: replace "git-clone" with "curl".
TODO: make "sudo" requirement optional

```bash
$ git clone git@github.com:misho-kr/docker-registry.all-in-one.git
$ cd docker-registry.all-in-one.git
$ ansible-playbook -i ansible/hosts ansible/site.yml
sudo password: ***

PLAY [build_hosts] ************************************************************
...

PLAY RECAP ********************************************************************
f22-docker : ok=33   changed=23   unreachable=0    failed=0

$ ls -l ansible/*.gz 
-rw-r--r--. 1 mkrastev users 206432549 Aug 22 16:25 ansible/docker-registry-dev.tar.gz
-rw-r--r--. 1 mkrastev users 204970276 Aug 22 16:25 ansible/docker-registry.tar.gz
```

You may need to add "-k" and/or "-K" parameters if password authentication is required 1) to login to the build host, 2) to execute sudo commands

## Requirements

To successfully execute the playbook some (minimal) requirements have to be satisfied.

* __SSH__ access to the build host
* __SUDO__ privileges on the build host

__Sudo__ is necessary to run the __docker__ commands because the playbook does not assume your account is member of the __docker__ group. Besides that, a few packages are required by the build procedure so if they are not available the package-install command will be invoked.

## Configuration

For flexibility there are paramaters that can be modified to change the build process to meet broader needs.

This section can be expanded if needed. For now it will only provide the locations of the parameter files.

* _ansible/hosts_
* _ansible/group_vars/all.yml_
* _ansible/roles/source_code/vars/main.yml_
* _ansible/roles/docker_images/defaults/main.yml_

Make sure to update the first file and set the desired build host (where the Docker images will be built) in the _build_host_ section.

## Playbook actions

In a nutshell, the playbook execution will proceed as follows:

* Check and install the necessary software packages on the build host
* Download the code for [docker-registry](https://github.com/dotcloud/docker-registry/archive/0.9.0.zip), [swift-driver](https://github.com/bacongobbler/docker-registry-driver-swift/archive/master.zip) and [elastic-search plugin](https://github.com/misho-kr/elasticsearchindex/archive/master.zip)
* Apply this [patch to the docker-registry code](https://gist.github.com/misho-kr/4face298975a8bcf01a6/download)
* Build Docker images -- _base_, _main_ and _dev_
* Export _main_ and _dev_ Docker images to tar file and transfer them to the local host
* Optionally tag the _main_ and _dev_ Docker images and push them to remote Docker registry

## Problem with GitHub http basic auth

Some GitHub sites (particularly private/corporate) have switched to mandatory token authentication for all access to public repositories, even for git-clone and downloads. The Ansible [get-url module](http://docs.ansible.com/get_url_module.html) supports [HTTP Basic Authentication](http://en.wikipedia.org/wiki/Basic_access_authentication) but the implementation depends on GitHub to send HTTP 401 (Unauthorized) response before the credentials (token) are sent. There are several workarounds for this problem, and there is one proper solution which is to add option to force the authentication and send the credentials even before the 401 error. Until that option is available in the official Ansible here is a Dockerized Ansible image which has the pending PRs already merged in.

The [Dockerfile is defined here](https://github.com/misho-kr/scripts-and-tools/tree/master/docker/patch-ansible) and is published as [Trusted Docker build](https://registry.hub.docker.com/u/misho1kr/ansible-force-basic-auth) so the __docker-run__ command will fetch it from the offical Docker Hub.

```bash
$ docker run -it --rm --privileged -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
	-v $PWD:/playbook -v $SSH_AUTH_SOCK:$SSH_AUTH_SOCK \
	misho1kr/ansible-force-basic-auth \
	    ansible-playbook -i ansible/hosts ansible/site.yml \
            -e ssl_certificate_domain="*.slc01.dev.ebayc3.com" \
            -u <username> -K
```

On system with SELinux enabled be sure to run these two commands to enable the mountig of volumes by the container.

```bash
$ chcon -Rt svirt_sandbox_file_t $SSH_AUTH_SOCK
$ chcon -Rt svirt_sandbox_file_t $PWD 
```

PS: In future releases of docker the __--privileged__ flag may not be needed, and maybe the __chcon__ commands either.
