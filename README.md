# Nginx Bosh Release

## SSL
makes certificate available in the following locations, use this yaml
```
#location
/var/vcap/jobs/nginx/ssl/<name>.crt
/var/vcap/jobs/nginx/ssl/<name>.key

#ops file
- type: replace
  path: /instance_groups/name=?/jobs/name=nginx/properties?/ssl?/certificates?/-
  value:
    name: certificate1
    certificate: |
      #### CERTIFICATE
    key: |
      #### Key

- type: replace
  path: /instance_groups/name=?/jobs/name=nginx/properties?/ssl?/certificates?/-
  value:
    name: certificate2
    certificate: |
      #### CERTIFICATE
    key: |
      #### Key

```

Simple bosh release that compiles nginx-1.12.0 stable with pcre-8.40 and zlib-1.2.11

Source files for these are located in src/nginx/

Manifests are in manifests/ and contain the following manifests:
- vbox-cloud-config.yml
  - example cloud configuration to set up this nginx release in virtualbox
- deployment.yml
  - example deployment configuration to use with the vbox cloud configuration
- deployment-website.yml
  - an example deployment with a website release included
- ops-instances.yml
  - this contains examples to increase the number of instances

# Release information
The release contains the following:
- package
- job

### Package
Package contains the following files:
- packages/nginx/spec
- packages/nginx/packaging

#### spec
spec covers information on the package and if there are any dependencies. It lists the files used in the package.
```
---
name: nginx

dependencies: []

files: [nginx/nginx-1.12.0.tar.gz, nginx/zlib-1.2.11.tar.gz, nginx/pcre-8.40.tar.gz]
```
#### packaging
packaging covers how to build the package, compiling it or whatever is needed. In this case we are compiling nginx from the documentation (https://www.nginx.com/resources/admin-guide/installing-nginx-open-source/)
```
set -e -x

echo "Extracting pcre..."
tar xzvf nginx/pcre-8.40.tar.gz

echo "Extracting zlib..."
tar xzvf nginx/zlib-1.2.11.tar.gz

echo "Extracting nginx..."
tar xzvf nginx/nginx-1.12.0.tar.gz

echo "Building nginx..."

pushd nginx-1.12.0
  ./configure \
    --with-debug \
    --prefix=${BOSH_INSTALL_TARGET} \
    --with-pcre=../pcre-8.40 \
    --with-zlib=../zlib-1.2.11 \
    --with-http_dav_module \
    --with-http_realip_module \

  make
  make install
popd
```
### Job
Job contains the following files
- jobs/nginx/monit
- jobs/nginx/spec
- jobs/nginx/templates/ctl.sh
- jobs/nginx/templates/nginx.conf.erb
- jobs/nginx/templates/pre-start.erb
- jobs/nginx/templates/fastcgi_params.erb

#### monit
Monit covers how the package is started/monitored for bosh to know what to do with it
```
check process nginx
  with pidfile /var/vcap/sys/run/nginx/nginx.pid
  start program "/var/vcap/jobs/nginx/bin/ctl start"
  stop program "/var/vcap/jobs/nginx/bin/ctl stop"
  group vcap
```
#### spec
Spec covers the specifications for the job and any default properties or properties in general, and which package they apply to
```
---
name: nginx

templates:
  ctl.sh: bin/ctl
  nginx.conf.erb: etc/nginx.conf
  pre-start.erb: bin/pre-start
  fastcgi_params.erb: etc/fastcgi_params

packages:
- nginx

properties:
  nginx_worker_processes:
    description: Nginx worker processes count
    default: 1
  nginx_worker_connections:
    description: Nginx worker connections
    default: 1024
  nginx_docroot:
    description: Nginx docroot
    default: /var/vcap/store/nginx/www/document_root
  nginx_server_name:
    description: domain name(s)
    default: localtest.local
```
In nginx, we are specifying some basic properties to update in the templates.

The templates will get copied from jobs/nginx/templates to the specified locations once deployed.

#### templates/ctl.sh
This is just a simple script that controls starting and stopping nginx and is used by monit
```
#!/bin/bash -e

JOB_NAME=nginx
BASE_DIR=/var/vcap
SYS_DIR=$BASE_DIR/sys
RUN_DIR=$SYS_DIR/run/$JOB_NAME
LOG_DIR=$SYS_DIR/log/$JOB_NAME
JOB_DIR=$BASE_DIR/jobs/$JOB_NAME
CONFIG_DIR=$JOB_DIR/etc
CONFIG_FILE=$CONFIG_DIR/nginx.conf
PERSISTENT=$BASE_DIR/store
PIDFILE=$RUN_DIR/$JOB_NAME.pid

mkdir -p $RUN_DIR $LOG_DIR $CONFIG_DIR

case $1 in

  start)
    $BASE_DIR/packages/nginx/sbin/$JOB_NAME -g "pid $PIDFILE;" -c $CONFIG_FILE
    ;;
  stop)
    kill $(cat $PIDFILE)
    ;;
  *)
    echo "Usage: ctl {start|stop}"
    ;;
esac
```
#### templates/nginx.conf.erb
This is just a simple nginx configuration that serves up the docroot static page

#### templates/pre-start.erb
This script is run before the package is installed/started, and it does some tasks that need to be performed before the application starts, in this case we want to make sure the docroot exists, and that the file index.html is present
```
#!/bin/bash -ex
NGINX_DIR=<%= p('nginx_docroot') %>
if [ ! -d $NGINX_DIR ]; then
  mkdir -p $NGINX_DIR
  cd $NGINX_DIR
  echo "It verks!" > index.html
  chown -R vcap:vcap $NGINX_DIR
fi
```

#### templates/fastcgi_params.erb
This isn't used anywhere in this example, but if you want to run php-fpm at some stage, this file needs to exist somewhere for nginx to find it, so it is placed in the location nginx would look for by default if you were to specify a php block in the nginx config like this.
```
location ~ \.php$ {
    try_files $uri =404;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
>>> include fastcgi_params;  <<< here
}
```


# Usage

## Getting started
Deploy a bosh directory into virtualbox, and load the cloud configuration
```
cd <path>/nginx-boshrelease
bosh -e vbox ucc manifests/vbox-cloud-config.yml
```
Create the release and upload it into the director
```
bosh create-release --force
bosh -e vbox upload-release
```
Add the route so you can access the server once its deployed
```
sudo route add -net 10.244.0.0/16 gw 192.168.50.6
```
Configure a vhost in manifests/vhost.yml
Run the deployment
```
bosh -e vbox -d nginx deploy manifests/deployment.yml -o manifests/vhost.yml
```
Watch as the director creates an nginx instance, you can visit the static page here: http://10.244.0.50

## Further examples
### Increase instances in network
Now that you have a single instance running, lets build up another using an operations file
```
bosh -e vbox -d nginx deploy manifests/vbox-deployment.yml -o manifests/ops-instances.yml
```
This will spin up a second instance which is available here: http://10.244.0.51

The code in the operations file is this
```
- type: replace
  path: /instance_groups/name=nginx/networks
  value:
    - name: default
      static_ips:
      - 10.244.0.50
      - 10.244.0.51

- type: replace
  path: /instance_groups/name=nginx/instances
  value: 2
```
The first block adds a second static IP address to the available IPs for the instance group called <b>nginx</b>.

The second block increases the number of instances to build from 1 to 2.

# Delete the deployment
Once you're done, you can delete the entire deployment
```
bosh -e vbox -d nginx deld
```
