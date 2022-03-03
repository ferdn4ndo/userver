# uServer

A docker-based web-hosting server stack based on micro-service containers.

**IMPORTANT: Work in progress!**

The following image shows all the components:

![uServer Diagram](https://github.com/ferdn4ndo/userver/blob/master/docs/userver_main_diagram.png)

## Current list of services

In order of build process.


* [userver-web](https://github.com/ferdn4ndo/userver-web): the HTTP and HTTPS core, as well as general health-check system. Services contained:
    * `userver-nginx`-proxy: based on [jwilder/nginx-proxy
](https://github.com/nginx-proxy/nginx-proxy) to serve as the reverse-proxy for the hosted domains;
    * `userver-letsencrypt`: based on [letsencrypt-nginx-proxy-companion](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion) handling the certificates and ensuring connections are made using HTTPS (SSL support and auto-renewal);
    * `userver-monitor`: based on [netdata](https://github.com/netdata/netdata) to act as the general health monitor;


* [userver-datamgr](https://github.com/ferdn4ndo/userver-datamgr): Data management microservices stack for persistent and ephemeral data, periodically backups and a client UI. Services contained:
    * `userver-postgres`: based on [PostgreSQL](https://hub.docker.com/_/postgres) for persistent data;
    * `userver-redis`: based on [Redis](https://hub.docker.com/_/redis) for non-persistent (ephemeral) data;
    * `userver-adminer`: based on [Adminer](https://hub.docker.com/_/adminer/) to serve as a DB UI interface;
    * `userver-databackup`: a custom implementation of [postgresql-backup-s3](https://github.com/itbm/postgresql-backup-s3) to perform periodic backups of the DB and act as a restoration tool when needed; 


* [userver-mailer](https://github.com/ferdn4ndo/userver-mailer): a mail microservice stack containing SMTP, IMAP and POP servers with periodically backup and a webmail client. Services contained:
    * `userver-mail`: based on [docker-mailserver](https://github.com/tomav/docker-mailserver) containing the SMTP, IMAP and POP servers;
    * `userver-mailbackup`: based on [tiberiuc/backup-service](https://github.com/tiberiuc/docker-backup-service) to perform periodically compressed backups of the mail accounts and upload them to a S3 bucket;
    * `userver-webmail`: based on [rainloop-webmail](https://github.com/RainLoop/rainloop-webmail) to serve as the webmail client interface.


* [userver-auth](https://github.com/ferdn4ndo/userver-auth): a custom single-container service based on [Flask](https://github.com/pallets/flask) to serve as the authentication provider using JWT among the hosted platforms.


* [userver-filemgr](https://github.com/ferdn4ndo/userver-filemgr): a custom single-container service based on Django and django-rest-framework to serve as the file management system with AWS S3 integration


## Setup steps (local deploy)

In order to run the stack locally, simply copy the environment template file `.env.template` into `.env` and edit it accordingly.

Then run `./run.sh` and wait until `=========  SETUP FINISHED! =========` appears.


## Setup steps (AWS EC2 deploy)

### Create the EC2 instance

If you already have a running EC2 instance, jump to [next step](#Connect-to-the-EC2-instance)

Connect to your Amazon EC2 console and launch a new `Amazon Linux 2 AMI (HVM), SSD Volume Type`, with sizing `t2.small` or greater.

Ensure that your security group attends the following inbound rule requisites:

| TYPE   | PROTOCOL | PORTS | ORIGIN         | DESCRIPTION                             |
|--------|----------|-------|----------------|-----------------------------------------|
| HTTP   | TCP      | 80    | 0.0.0.0/0 ::/0 | Nginx reverse proxy non-secured traffic |
| HTTPS  | TCP      | 443   | 0.0.0.0/0 ::/0 | Nginx reverse proxy secured traffic     |
| POP3   | TCP      | 110   | 0.0.0.0/0 ::/0 | POP3 mail exchange non-secured traffic  |
| IMAP   | TCP      | 143   | 0.0.0.0/0 ::/0 |                                         |
| SMTPS  | TCP      | 465   | 0.0.0.0/0 ::/0 |                                         |
| SMTP   | TCP      | 25    | 0.0.0.0/0 ::/0 | MX SMTP non-secured (main) traffic      |
| Custom | TCP      | 587   | 0.0.0.0/0 ::/0 | Mail sending through MUAs               |
| SSH    | TCP      | 22    | <your-ip>/32   | Allow connections to your instance      |

Store your key pair locally in a safe place and take note. We'll consider `/PATH/TO/YOUR/PEM/FILE` as its path here. Remember to change it before running the commands. 

**Also, double check if your PEM file has the right permissions and use `chmod 400 /PATH/TO/YOUR/PEM/FILE` to fix it.**

### Connect to the EC2 instance

Having your instance Public DNS IPv4 record (should look similar to `ec2-18-258-101-120.compute-1.amazonaws.com`) and your `/PATH/TO/YOUR/PEM/FILE`, adjust the following command properly and connect to your instance:

```
ssh -i /PATH/TO/YOUR/PEM/FILE ec2-user@<your-instance-Public-DNS-(IPv4)>
```

**Note:** if you're asked about being sure to connect as the authenticity of your host can't be established, type 'yes'. This is needed in the first time connecting. 

### Prepare your instance

We're assuming you have a fresh started EC2 instance. Feel free to tweak the script accordingly if that's not the case.

This script is based in the [AWS Developers Guide - Docker on an Amazon EC2 instance](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/docker-basics.html) article. Take a look into it to ensure this is updated. 

```shell script
# Update the installed packages and package cache on your instance.
sudo yum update -y

# Install the most recent Docker Community Edition package.
# For Amazon Linux 2
sudo amazon-linux-extras install -y docker git

# If you were in a Amazon Linux (1) instance instead, use the following command
# sudo yum install docker

# Start the Docker service.
sudo service docker start

# Add the ec2-user to the docker group so you can execute Docker commands without using sudo.
sudo usermod -a -G docker ec2-user
```

After that, log out and log back in again to pick up the new docker group permissions. 
Do this by closing your current SSH terminal (try `Ctrl+D`) and opening it once again, using the same command as before on [Connect to the EC2 instance](Connect-to-the-EC2-instance).

As you log in again, check that the ec2-user can run Docker commands without sudo by running the following command:

```
docker info
```

You should see a lot of information about your docker daemon service. A fresh machine should look like:

```
Client:
 Debug Mode: false

Server:
 Containers: 0
  Running: 0
  Paused: 0
  Stopped: 0
 Images: 0
 Server Version: 19.03.6-ce
 Storage Driver: overlay2
 ...
```

**Note:** if you face any issue running this last command, try first restarting your instance through the EC2 console interface.

### Clone this repo

Make sure you have git installed. Fresh created Linux 2 AMI instances doesn't have git installed. If you're not sure, run:

```
sudo yum install -y git
```

Then clone this repository:

```
git clone https://github.com/ferdn4ndo/userver.git
```

Copy the environment template file `.env.template` into `.env` and edit it accordingly.

### Run

Navigate through the root project folder by using `cd userver` and run:
 
```
./run.sh
```

Take a look at it before. It's always a good practice.

### Stop

To stop all the running uServer services, run:
 
```
./stop.sh
```

### Remove

If you want to start fresh or simply remove all the services files, images and data, run:

```
./remove.sh
```

**WARNING**: This will remove **ALL** the uServer containers and their data! Don't run this in production unless you're
really sure about that.

## Testing

Under development (see `tests/README.md`) as the proprietary services already contains its testing suit. However, a more robust testing approach reproducing the same environment as an EC2 instance locally to run all the services together is a great achievement.


## Contributors

[ferdn4ndo](https://github.com/ferdn4ndo)


Any help is appreciated! Feel free to review / open an issue / fork / make a PR.
