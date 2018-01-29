Configure OVD SSL Listeners
===========================

This scripts updates the SSL settings of the local Oracle OVD instance.

Instance properties are sourced from addition env file. 


### Steps

- new keystores are created with the content extracted from reference 
  keystores (trust and identity)
- the new identity certificate is added to the EMAGENT wallet
- the keystores are loaded and registered in Fusion
- configure listeners: use both new keystores, set passphrases
- restart ovd component
- reregister ovd instance in weblogic domain, needed when changing
  the admin gateway properties


### Passphrase Handling

Passwords are read from several files located in `.key` subdir:

- `.keys/weblogic`     weblogic user
- `.keys/orcladmin`    cn=orcladmin
- `.keys/bakeystore`   reference keystore passphrase
- `.keys/bakey`        reference identity keystore private key passphrase
