# kscripts
A collection of scripts around Kubernetes management

## Prerequisites

These scripts are written to run on a Mac, using Bash 4.  They also depend on certain tools being installed.  The `prerequities.sh` script will evaluate your system, and report which tools, if any, are missing.

## Configuring SSH

In order to shorten certain commands using SCP and SSH, your ssh_config must be set up, either globally or in your user's `$HOME/.ssh/config` file.  In particular:

```
Host *.mylabserver.com
 User user
 IdentityFile ~/.ssh/la_cka
 StrictHostKeyChecking no
 IdentitiesOnly yes
```

This specifies that for any operation against a machine in the `mylabserver.com` domain, the user will be `user`, it will use an identity file named `la_cka`, etc.  The identity file may be generated using the `setup-ssh-keys.sh` script, which will generate a new public / private key token, and copy the public key to a series of target machines.
