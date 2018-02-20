Configure OVD SSL Listeners
===========================

This scripts updates the SSL settings of the local Oracle OVD instance.

Instance properties are sourced from addition env file. 


## Steps

- new keystores are created with the content extracted from reference 
  keystores (trust and identity)
- the new identity certificate is added to the EMAGENT wallet
- the keystores are loaded and registered in Fusion
- configure listeners: use both new keystores, set passphrases
- restart ovd component
- reregister ovd instance in weblogic domain, needed when changing
  the admin gateway properties


## Passphrase Handling

Passwords are read from several files located in `.key` subdir:

- `.keys/weblogic`     weblogic user
- `.keys/orcladmin`    cn=orcladmin
- `.keys/bakeystore`   reference keystore passphrase
- `.keys/bakey`        reference identity keystore private key passphrase


## Project Files

    ovd.env             general environment (if not already existing/set)
    ovd-configssl.env   additional instance config
    ovd-configssl.sh    actual configuration script
    init-pass-files.sh  script for creating password files

## Usage

Create config files from templates:

    $ cp ovd.env.sample            ovd.env
    $ cp ovd-configssl.env.sample  ovd-configssl.env
    $ cp init-pass-files.sh.sample init-pass-files.sh

Edit the config files and the create password script:

    $ vi ovd-configssl.env ovd.env init-pass-files.sh

Create the password files:

    $ ./init-pass-files.sh

Run the configuration:

    $ ./ovd-configssl.sh

Discard the pasword files:

    $ rm -rf .keys


## Common Problems

There are several bugs in OVD that effect SSL listeners.  Be aware of
them when you use the GUI.  The product documentation describes in
detail how to configure listeners [Chapter 12: Creating and Managing
Oracle Virtual Directory
Listeners](https://docs.oracle.com/middleware/11119/ovd/ovd-admin/basic_listeners.htm#OVDAG281).

### SSL Listener Creation

When you create a new SSL listener using the GUI, the newly created
configuration is not correct and has to be corrected. This can be done
by WLST or by manually editing the "listener_os.xml" file while the
services are down.

### Cipher Suites

The cipher suites list shall be empty (no ciphers shall be stated) and the 
attribute "includeAnonCiphers" must be set to true.

### Blocking Mode

The setting "useNIO" shall be set to false.


### Reference Configuration

```
<ldap id="TLS" version="3">
    <port>9999</port>
    <host>0.0.0.0</host>
    <threads>10</threads>
    <active>true</active>
    <ssl enabled="false">
        <protocols>TLSv1,SSLv2Hello</protocols>
        <cipherSuites includeAnonCiphers="true"/>
        <authType>Server</authType>
        <keyStore password="{AES-CBC}b2vWJAN48ufpbxla9gohlj/M+eBP/9FLwh6tLfiWF0o=">TLSkeyStore.jks</keyStore>
        <trustStore password="{AES-CBC}rOk44ucwkpQ2QRcTDK4bJRklj/OmALyUWQMjQAYoNJY=">TLSkeyStore.jks</trustStore>
    </ssl>
    <extendedOps/>
    <anonymousBind>Allow</anonymousBind>
    <workQueueCapacity>100</workQueueCapacity>
    <allowStartTLS>false</allowStartTLS>
    <socketOptions>
        <backlog>128</backlog>
        <reuseAddress>false</reuseAddress>
        <keepAlive>false</keepAlive>
        <tcpNoDelay>true</tcpNoDelay>
        <readTimeout>0</readTimeout>
    </socketOptions>
    <useNIO>false</useNIO>
</ldap>
```

