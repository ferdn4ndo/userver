# uServer

A complete web applications hosting server stack based on Docker micro-service containers.

IMPORTANT: Work in progress!

## Setup steps

### Create the EC2 instance

If you already have a running EC2 instance, jump to [next step](#Connect-to-the-EC2-instance)

Connect to your Amazon EC2 console and launch a new `Amazon Linux 2 AMI (HVM), SSD Volume Type`, with sizing `t2.small` or greater.

Ensure that your security group attends the following inbound rule requisites:

| TYPE   | PROTOCOL | PORTS | ORIGIN         | DESCRIPTION                             |
|--------|----------|-------|----------------|-----------------------------------------|
| HTTP   | TCP      | 80    | 0.0.0.0/0 ::/0 | Nginx reverse proxy non-secured traffic |
| HTTPS  | TCP      | 443   | 0.0.0.0/0 ::/0 | Nginx reverse proxy secured traffic     |
| POP3   | TCP      | 110   | 0.0.0.0/0 ::/0 | POP3 mail exchange non-secured traffic  |
| IMAP   |          | 143   | 0.0.0.0/0 ::/0 |                                         |
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

### Run the setup

Navigate through the root project folder by using `cd userver` and run:
 
```
chmod +x ./setup.sh && ./setup.sh
```

Take a look at it before. It's always a good practice.



