[Docker Registry](https://github.com/dotcloud/docker-registry)
==============================================================

This project is based on the open-sourced Docker registry. It adds several drivers, runs all processes in a Docker container, and provides [Ansible playbook](ansible/) to automate the process of building new Docker image of the registry.

## Goals

Build an image of the Docker registry optimized for performance that can be run by multiple containers to provide high availability (HA) and scalability to meet growing demands.

All traffic to the Docker registry must be encrypted and protected with properly signed SSL certificates. Unencryted HTTP traffic is allowed only inside the container.

Docker images should be stored on remote shared media to enable simultaneous access from multiple clients.

#### Components

To meet these goals the Docker registry container runs several processes managed by [supervisord](http://supervisord.org):

* [Nginx](http://nginx.org/en/docs) frontend to accept HTTPS connections, and optionally handle user authentication
* [Redis](http://redis.io) database to optimize the access to docker image metadata by reducing the read time from remote backends
* [Elasticsearch](https://github.com/misho-kr/elasticsearchindex) to index all images and tags make them searchable
* [Swift backend](https://github.com/bacongobbler/docker-registry-driver-swift) to store docker images and metadata outside of the container so it can be accessed by other containers
* [Logrotate](http://www.linuxcommand.org/man_pages/logrotate8.html) to keep logfiles under control

#### Multiple flavors

One size does not fit all, that is why the Docker regitry can be started in different modes -- one that maximizes the performance and availability, and another one that is suitable for developers who want to run their own (single-instance) registry.

#### Caching with Redis database

Redis database can be used for caching *only* with single-instance Docker registry.

When multiple containers share the same swift container the Redis cache __must not__ be used, because it will lead to incorrect results. To make easier to avoid this mistake there are two docker images -- _main_ one that does not use redis and _dev_ one that does. The latter is provided for developers who want to run their own (single-instance) docker registry.

## Build Docker images

Run this [Ansible playbook](ansible/) to build 3 Docker images:

* __Base__ image that has all software packages installed (except for _redis_) but without any configuration files
* __Main__ image with preloaded configuration files for _nginx_, _swift_ and _elastic search_, but without _redis_
* __Dev__  image which includes _redis_ database for improved performance

Pay attention to where to find the images:

1. Local docker repository on the build host (defined in the inventory file of the Ansbile playbook)
1. Optionally, _main_ and _dev_ images pushed to remote Docker repository (defined in playbook)
1. Gziped tarfiles of _main_ and _dev_ images in the current local directory

```bash
$ ssh <ansible-build-host> 'docker images'
REPOSITORY               TAG       IMAGE ID       CREATED             VIRTUAL SIZE
docker-registry          latest    4973556af2f1   About an hour ago   538 MB
docker-registry-dev      latest    3b0b248d9fbb   About an hour ago   545.6 MB
docker-registry-base     latest    452e4cce1266   About an hour ago   537.9 MB
...

$ ls -l ansible/
total 401976
-rw-r--r--. 1 mkrastev users 206521247 Aug 21 15:49 docker-registry-dev.tar.gz
-rw-r--r--. 1 mkrastev users 205067162 Aug 21 15:49 docker-registry.tar.gz
...
```

## Start up

The docker images do not have the credentials to connect to the swift backend. That information has to be passed to the containers at the command line.

```
$ docker run -d -p 80:8080 -p 443:8443 --name=docker-registry -e OS_PASSWORD=<swift-password> \
    docker-registry
```

* Pass "-e OS_CONTAINER=my-docker-registry" to the _docker-run_ command

It is recommended to use unique swift container for each registry (except for multi-instance docker registry) to avoid name clashes and conflicts between distinct registries. Set this environment variable:

The example above assumes you know the password for the tenant and username that is configured in the docker registry image. If that is not the case then use your account -- there are few more variables that have to be overriden:

* OS_AUTH_URL
* OS_REGION_NAME
* OS_TENANT_NAME
* OS_USERNAME

### Chicken and egg dilemma

To start Docker container that will run Docker registry one needs ... another Docker registry to pull the image from. How do you boostrap the very first Docker registry?

Use the [docker load command](https://docs.docker.com/reference/commandline/cli/#load) to bring the tar file of the Docker registry image into the local docker registry. The tar file can acquired by either:

* [Run the Ansible playbook](ansible/) and look inside the ansible folder
* Copy one from the available in the C3 Swift container _docker-registry.bootstrap_ of GPAAS_DOCKER tenant, then launch the Docker container as descibed above

```bash
$ echo $OS_TENANT_NAME
GPAAS_DOCKER
$ swift list docker-registry.bootstrap
docker-registry-dev.tar.gz
docker-registry.tar.gz
```

## Docker registry flavors

The several configurations, called _flavors_, in which the Docker registry can be run. Look in the (config/docker-registry) file and review the
definitions at the end of the file.

* Default flavor is __qa__ which includes Swift backend, ElasticSearch index, all running in the non-production environment, but no Redis cache

This setting may change. To confirm the default flavor open the [Dockerfile](Dockerfile.setup) and find the __SETTINGS_FLAVOR__ environment variable. Note that the value of the flavor can overriden at runtime with command-line arguments. For example:

* There is __devel__ flavor which has all components started, including Redis cache

The Redis cache will speed up repeared __read__ operations from the Swift backend, which is desirable but keep in mind that it can be used only when the registry is running in single-instance mode.

* Pass "-e SETTINGS_FLAVOR=qa-noes" to the _docker-run_ command

This will activate the predefined __qa-noes__ flavor which does not load the ElasticSearch plugin. This flavor is useful if the ElasticSearch cluster experiences problems that affect the normal execution of _docker-push_ operations against the Docker registry.

## Troubleshooting

Suggestions for what to look for and where when the docker-registry does not perform as expected. The list is not exhaustive and will benefit from more additions.

#### Ping the registry

```bash
$ curl -s http://docker-registry-377996.slc01.dev.ebayc3.com
"docker-registry server (qa) (v0.8.1)"

$ curl -s http://docker-registry-377996.slc01.dev.ebayc3.com/_ping
true
```

#### Query the registry status

```bash
$ curl -s http://docker-registry-377996/_status | python -m json.tool
{
    "failures": {
        "redis": "unconfigured"
    },
    "host": "e55fb38366e1",
    "services": [
        "redis",
        "storage"
    ]
}
```

#### Query the Nginx status

[Nginx status page](http://wiki.nginx.org/HttpStubStatusModule) can give realtime data about [Nginx’s health](https://rtcamp.com/tutorials/nginx/status-page).

```bash
$ curl -s http://docker-registry/nginx_status
Active connections: 1
server accepts handled requests
 119 119 116
Reading: 0 Writing: 1 Waiting: 0
```

* Active connections – Number of all open connections. This doesn’t mean number of users. A single user, for a single pageview can open many concurrent connections to your server.
* Server accepts handled requests – This shows three values.
 * First is total accepted connections.
 * Second is total handled connections. Usually first 2 values are same.
 * Third value is number of and handles requests. This is usually greater than second value.
 * Dividing third-value by second-one will give you number of requests per connection handled by Nginx. In above example, 116/119, 0.98 requests per connections.
* Reading – nginx reads request header
* Writing – nginx reads request body, processes request, or writes response to a client
* Waiting – keep-alive connections, actually it is active – (reading + writing).This value depends on [keepalive-timeout](http://wiki.nginx.org/HttpCoreModule#keepalive_timeout). Do not confuse non-zero waiting value for poor performance. It can be ignored. Although, you can force zero waiting by setting <span style="color: red">keepalive_timeout 0;</snap>

#### Look inside the Docker container

* This initial version of the docker registry writes to local logfiles. In case of problems the only option is to login to the container to search the logfiles.
* The container does not run _ssh_ daemon so get access to the local logfiles so you have to:
 * First login to the Docker host that runs the registry containers(s)
 * Then enter the running container(s) with the [nsenter command](http://blog.docker.com/2014/06/why-you-dont-need-to-run-sshd-in-docker/).

```bash
$ docker ps
CONTAINER ID        IMAGE                                                                    COMMAND                CREATED             STATUS              PORTS                                                              NAMES
2745c3af53ac        docker-registry.fqdn/docker-registry-dev:latest   supervisord -c /etc/   55 minutes ago      Up 55 minutes       0.0.0.0:82->80/tcp, 0.0.0.0:445->443/tcp, 0.0.0.0:5002->5000/tcp   docker-registry-dev
27ec04b1eb17        docker-registry.fqdn/docker-registry:latest       supervisord -c /etc/   55 minutes ago      Up 55 minutes       0.0.0.0:81->80/tcp, 0.0.0.0:444->443/tcp                           docker-registry-test
408d5f27f7b0        docker-registry.fqdn:80/mkrastev/docker-registry:devtest   supervisord -c /etc/   7 days ago          Up About an hour    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:5000->5000/tcp   docker-registry

$ sudo nsenter -i -m -n -p -u -t $(d inspect -f '{{ .State.Pid }}' docker-registry)
root@408d5f27f7b0:/#
root@408d5f27f7b0:/# ls -l /var/log/nginx/
total 60
-rw-r--r-- 1 root root     0 Aug  5 00:52 error.log
-rw-r--r-- 1 root root 60433 Aug  5 00:58 nginx-http-access.log
-rw-r--r-- 1 root root     0 Aug  5 00:52 nginx-https-access.log
root@408d5f27f7b0:/#
root@408d5f27f7b0:/# ls -l /var/log/supervisor/
total 672
-rw-r--r-- 1 root root 642772 Aug  5 00:58 docker-registry.log
-rw------- 1 root root      0 Aug  5 00:52 logrotate-stderr---supervisor-PLOK1i.log
-rw-r--r-- 1 root root    387 Aug  5 00:52 logrotate.log
-rw-r--r-- 1 root root  29404 Aug  5 00:58 nginx-stderr.log
-rw------- 1 root root      0 Aug  5 00:52 nginx-stdout---supervisor-xslM0q.log
-rw------- 1 root root      0 Aug  5 00:52 registry-stderr---supervisor-GHivia.log
-rw-r--r-- 1 root root   1563 Aug  5 00:52 supervisord.log
```
