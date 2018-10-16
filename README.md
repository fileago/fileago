# FileAgo

**FileAgo** is a self-hosted file storage and collaboration platform for teams and businesses.

Visit [fileago.com](https://www.fileago.com) for more details.

## Requirements

- Linux machine with atleast 2GB RAM, 5GB free disk space
- Docker
- Git

## Installation

### For quick testing/demo

```shell
cd /root
git clone https://github.com/fileago/fileago.git
cd fileago
docker-compose up -d
```

Visit https://localhost/ to begin the configuration process. Use the following information (exactly as it is given below) to fill in the form:

| Field          | Value  |
| -------------- | ------ |
| Neo4j Host     | db     |
| Neo4j Port     | 7474   |
| Neo4j Username | neo4j  |
| Neo4j Password | mypass |

Once the initial setup is over, login as `admin` and create users and groups. Logout from the `admin`account, and begin using FileAgo as one of the users you have created (use email address to login as normal users).

#### Cleanup

**CAUTION: only execute the below commands if you wish to remove FileAgo and all its data from your machine.**

```shell
cd /root/fileago
docker-compose stop
docker-compose rm -f
```

### In production

#### Prerequisites

1. Make sure that the hostname of the server resolves properly through DNS
2. Purchase a valid SSL certificate for the host, or create one using [Let's Encrypt](https://letsencrypt.org/)

Create a directory to store FileAgo data:

```shell
mkdir -p /opt/fileago/nginx
```

**NOTE:** `/opt/fileago` is also the base directory used by FileAgo (and is configured in `.env` file)

Copy the SSL key and certificate into the newly created directory. In case of Let's Encrypt, the commands will be like:

```shell
cp /etc/letsencrypt/live/<HOSTNAME>/fullchain.pem /opt/fileago/nginx/cert.crt
cp /etc/letsencrypt/live/<HOSTNAME>/privkey.pem /opt/fileago/nginx/cert.key
```

#### Installation

```shell
cd /root
git clone https://github.com/fileago/fileago.git
cd fileago
```

Edit `settings.env`file and set value of `WEBHOSTNAME` to the server hostname. Start the install by executing:

```shell
docker-compose -f docker-compose-prod.yml up -d
```

Visit https://HOSTNAME to begin the configuration process. Use the following information (exactly as it is given below) to fill in the form:

| Field          | Value        |
| -------------- | ------------ |
| Neo4j Host     | db           |
| Neo4j Port     | 7474         |
| Neo4j Username | neo4j        |
| Neo4j Password | mysecurepass |

Once the initial setup is over, login as `admin` and create users and groups. Logout from the `admin`account, and begin using FileAgo as one of the users you have created (use email address to login as normal users).

#### Cleanup

**CAUTION: only execute the below commands if you wish to remove FileAgo and all its data from your machine.**

```shell
cd /root/fileago
docker-compose -f docker-compose-prod.yml stop
docker-compose -f docker-compose-prod.yml rm -f
rm -rf /opt/fileago
```

## Questions?

Contact [support@fileago.com](mailto:support@fileago.com) 



