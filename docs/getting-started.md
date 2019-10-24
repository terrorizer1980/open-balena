# OpenBalena Getting Started Guide

This guide will walk you through the steps of deploying an openBalena server, that together with balena CLI will enable you to create and manage your device fleet running on your own infrastructure, on any VPS such as AWS, Google Cloud, Digital Ocean or any other VPS provider.

## Setting up your own openBalena Instance on a VPS

For this we are going to setup a bare Ubuntu 18.04 x64 server.

### Installing dependencies

Before we get started setting up our balena environment, first we need to install a few tools and make sure our machine is up to date.

1. Log into your new server:

    ```
    $ ssh root@your_server_ip
    ```

2. Update all initial software:

    ```
    $ apt-get update && apt-get install -y build-essential git
    ```

3. Create a balena user:

    ```
    $ adduser balena
    ```

4. Add user admin permission:

    ```
    $ usermod -aG sudo balena
    ```

5. Install docker:

    ```
    $ apt-get install docker.io
    ```

6. Add `balena` user to `docker` group:

    ```
    usermod -aG docker balena
    ```

7. Install docker-compose:

    ```
    $ curl -L https://github.com/docker/compose/releases/download/1.24.0/docker-compose-Linux-x86_64 -o /usr/local/bin/docker-compose
    $ chmod +x /usr/local/bin/docker-compose
    ```

    Test your docker-compose installation with `$ docker-compose --version`.

8. Install OpenSSL:

    ```
    apt-get install libssl-dev
    ```

9. Install nodejs:

    ```
    apt-get install nodejs
    ```

10. Install NPM:

    ```
    apt-get install npm
    ```

### Installing openBalena

With all the required software installed, we can go ahead and install openBalena.

1. Clone openBalena project to your home folder with:

    ```
    git clone https://github.com/balena-io/open-balena.git ~/open-balena
    ```

2. Change into the `open-balena` directory and run the configuration script. This will create a new directory, `config`, and generate appropriate SSL certificates and configuration for the instance. The email and password provided will be used to create the superuser account, which you will use to authenticate against the system.

    ```
    $ ./scripts/quickstart -U <email@address> -P <password>
    ```

3. You may optionally configure the instance to run under a custom domain name. The default is `openbalena.local`.  In this guide we will setup using the domain `mydomain.com`, so in this case we will use:

    ```
    $ ./scripts/quickstart -U <email@address> -P <password> -d mydomain.com
    ```

    For more available options, see the script's help:

    ```
    $ ./scripts/quickstart -h
    ```

4. At this point we are ready to start our openBalena instance with:

    ```
    $ ./scripts/compose up -d
    ```

5. You can stop the instance with:

    ```
    $ ./scripts/compose stop
    ```

## Domain Configuration

In order to be able to reach your openBalena instance, a few CNAME addresses must to be configured and pointing to your server.

```
api.mydomain.com
registry.mydomain.com
vpn.mydomain.com
s3.mydomain.com
```

## Installing the CLI Client

After getting the openBalena server up and running, we need to install in our local machine the balena CLI, a command-line interface that will be used to manage all the devices and be the link between you and the server.

1. Install the client following the instructions [available
   here](https://github.com/balena-io/balena-cli/blob/master/INSTALL.md)

2. Point balena-cli to your server by setting `balenaUrl` in `~/.balenarc.yml` to your server domain name, eg:

    ```
    balenaUrl: "mydomain.com"
    ```

## Install self-signed certificates

When we create the openBalena instance, it generated a few self-signed certificates that we will need to use in order for our local machine and devices to connect to the server.

On the computer you installed balena-cli on, download the `ca.crt` certificate from the server and install it. In our current example, the openBalena instance is installed on `~/open-balena/` so the certificate will be in `~/open-balena/config/certs/root/ca.crt`. Then instruct balena-cli to use the new certificate:


```
$ export NODE_EXTRA_CA_CERTS=~/open-balena/config/certs/root/ca.crt
```

You will also need to install the certificate system-wide:

### On Linux:

```
$ sudo cp ca.crt /usr/local/share/ca-certificates/ca.crt
$ sudo update-ca-certificates
$ sudo systemctl restart docker
```

### On macOS:

```
$ sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/ca.crt

$ osascript -e 'quit app "Docker"' && open -a Docker
```

### On Windows:

```
$ certutil -addstore -f "ROOT" ca.crt
```

> **IMPORTANT:** You must restart the Docker daemon for it to pick up your newly trusted CA certificate. Without restarting Docker you will not be able to push images to the openBalena registry.

## Deploy our first application

At this point, we can log in to our server and create our first application.

#### 1) Login to openBalena

Type `balena login`, select `Credentials` and use the super user information generated previously.

#### 2) Creating the application

Now we can create our first application with `balena app create myApp`
From there you will be able to select which device you will be working with, for example a Raspberry Pi 3.

#### 3) Generating the image file

Before moving on, lets make  sure we have our application created

```
$ balena apps
ID APP NAME DEVICE TYPE  ONLINE DEVICES DEVICE COUNT
1  myApp    raspberrypi3
```

Once we have some apps it’s time to start provisioning devices into them, to do this we need to first download an balenaOS image for our device type from https://balena.io/os . As we are deploying a Raspberry Pi 3 device, we can go to https://balena.io/os/#downloads-raspberrypi and download the image for it.

After having downloaded the operating system image, unzip it somewhere locally, and then use the balena CLI to configure it for our openBalena instance. This can be done as follows:

```
balena os configure ~/Downloads/balenaos-raspberrypi3-2.22.1+rev1-dev-v7.25.3.img --app myApp
```

Once the image is configured with network credentials and keys to connect to our openBalena instance we can use https://etcher.io to flash it onto our SD card and then boot the device up.

After about 30 seconds we should be able to see our newly provisioned device in our app, to do this we run `balena devices`:

```
$ balena devices
ID UUID    DEVICE NAME     DEVICE TYPE  APPLICATION NAME STATUS IS ONLINE SUPERVISOR VERSION OS VERSION
4  59d7700 winter-tree     raspberrypi3 myApp            Idle   true      7.25.3             balenaOS 2.22.1+rev1
```

If we want to inspect the device more closely we can use the devices UUID as follows:

```
$ balena device 59d7700
== WINTER TREE
ID:                 4
DEVICE TYPE:        raspberrypi3
STATUS:             online
IS ONLINE:          true
IP ADDRESS:         192.168.43.247
APPLICATION NAME:   myApp
UUID:               59d7700755ec5de06783eda8034c9d3d
SUPERVISOR VERSION: 7.25.3
OS VERSION:         balenaOS 2.22.1+rev1
```

Alright, so we have some devices setup and connected to our openBalena instance, now its time deploy some code. In openBalena, there is no cloud builder service, so all of the building of containers needs to happen locally with the CLI.

For this example, I we will deploy an example project using a Raspberry Pi 3 and a Sense Hat from https://github.com/balena-io-playground/sense-snake.

Lets clone this repo to our computer and push it to the device we just provisioned:

```
git clone https://github.com/balena-io-playground/sense-snake.git
cd sense-snake
balena deploy myApp --logs --source . --emulated
```

Note that in the deploy code above we added `--emulated` to the end, this is because we are building a container for the Raspberry Pi, which has an ARM architecture while our local machine uses an x86_64 architecture.

```
[Info]    Compose file detected
[Info]    Everything is up to date (use --build to force a rebuild)
[Info]    Creating release...
[Info]    Pushing images to registry...
[Info]    Saving release...
[Success] Deploy succeeded!
[Success] Release: f62a74c220b92949ec78761c74366046

			    \
			     \
			      \\
			       \\
			        >\/7
			    _.-(6'  \
			   (=___._/` \
			        )  \ |
			       /   / |
			      /    > /
			     j    < _\
			 _.-' :      ``.
			 \ r=._\        `.
			<`\\_  \         .`-.
			 \ r-7  `-. ._  ' .  `\
			  \`,      `-.`7  7)   )
			   \/         \|  \'  / `-._
			              ||    .'
			               \\  (
			                >\  >
			            ,.-' >.'
			           <.'_.''
			             <'

```

After seeing the unicorn, we can grab some coffee while the code is pushed to the device.
In a couple minutes you will notice 