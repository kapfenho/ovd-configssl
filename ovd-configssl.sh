#!/bin/sh -x
#
#  This scripts updates the SSL settings of the local OVD instance.
#  Instance properties are sourced from addition env file. 
#
#  - new keystores are created with the content extracted from reference 
#    keystores (trust and identity)
#  - the new identity certificate is added to the EMAGENT wallet
#  - the keystores are loaded and registered in Fusion
#  - configure listeners: use both new keystores, set passphrases
#  - restart ovd component
#  - reregister ovd instance in weblogic domain, needed when changing
#    the admin gateway properties
#
#  Passwords are read from several files located in .key subdir:
#  - .keys/weblogic     weblogic user
#  - .keys/orcladmin    cn=orcladmin
#  - .keys/bakeystore   reference keystore passphrase
#  - .keys/bakey        reference identity keystore private key passphrase
#
#  2018-01-29, horst.kapfenberger@agoracon.at
#

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
[ -z "$INSTANCE_NAME"      ] && source $dir/ovd.env
[ -z "$REF_TRUST_KEYSTORE" ] && source $dir/ovd-configssl.env

set -o errexit
set -o nounset

# temporary working dir
wdir=$(mktemp -d -t tmp.XXXXXXXX)
ovdprop=$wdir/ovd.prop

# cleanup of temporary data
#
cleanup()
{
    rm -rf "$wdir"
}
trap cleanup EXIT


# create temporary keystores for import, named trust.jks and ident.jks 
# in the work-temp-dir
#
create_keystores()
{
    # trust keystore
    # copy reference keystore and merge oracle default trust store into 
    # new trust store - perhaps not needed. additional tests recommended
    
    cp -p "$REF_TRUST_KEYSTORE" "$wdir/trust.jks"
    
    keytool -importkeystore \
            -srckeystore "$OVD_CONFIG_DIR/keystores/keys.jks" \
            -destkeystore "${wdir}/trust.jks" \
            -srcstorepass:file "${dir}/.keys/orcladmin" \
            -deststorepass:file "${dir}/.keys/bakeystore" \
            -noprompt
    
    # identity keystore
    # create new keystore with the private key and certificate aliased 
    # with the FQDN of the host we are running on
    
    keytool -importkeystore \
            -srckeystore "$REF_IDENT_KEYSTORE" \
            -destkeystore "${wdir}/ident.jks" \
            -srcalias "$(hostname -f)" \
            -srcstorepass:file "${dir}/.keys/bakeystore" \
            -srckeypass:file "${dir}/.keys/bakey" \
            -destkeypass:file "${dir}/.keys/bakeystore" \
            -deststorepass:file "${dir}/.keys/bakeystore" \
            -noprompt
}


# add service certificate to emagent
#
emagent_add_cert()
{
  local wallet=$INSTANCE_HOME/EMAGENT/EMAGENT/sysman/config/monwallet
  local pem=$wdir/cert.pem

  keytool -exportcert \
          -keystore "$REF_IDENT_KEYSTORE" \
          -storepass:file "${dir}/.keys/bakeystore" \
          -alias "$(hostname -f)" \
          -rfc -file "$pem"

  $ORACLE_COMMON/bin/orapki wallet add \
          -wallet $wallet \
          -cert $pem \
          -trusted_cert -pwd welcome
}


# list keystore to stdout
#
show_keystores()
{
    printf "\n\n*** Trust keystore ***\n"
    keytool -list -keystore "$wdir/trust.jks" \
      -storepass:file "${dir}/.keys/bakeystore"

    printf "\n\n*** Identity keystore ***\n"
    keytool -list -keystore "$wdir/ident.jks" \
      -storepass:file "${dir}/.keys/bakeystore"
}


# weblogic: import keystores for ovd and configure TLS for LDAPS and 
# Admin Gateway listeners
#
update_keystore()
{
    local _wlspass="$(cat ${dir}/.keys/weblogic)"
    local _ovdtrustpass="$(cat ${dir}/.keys/bakeystore)"
    local _ovdidentpass="$(cat ${dir}/.keys/bakeystore)"
    
    local _wlst="connect('$WLS_USER','$_wlspass','t3://$ADMIN_HOST:$ADMIN_PORT')
importKeyStore('$INSTANCE_NAME','$OVD_INSTANCE_NAME','ovd','$OVD_TRUST_NEW','$_ovdtrustpass','$wdir/trust.jks')
importKeyStore('$INSTANCE_NAME','$OVD_INSTANCE_NAME','ovd','$OVD_IDENT_NEW','$_ovdidentpass','$wdir/ident.jks')
exit()
"
    echo "${_wlst}" | ${ORACLE_COMMON}/common/bin/wlst.sh
}


# update specified listener ssl settings, config file $ovdprop must  
# already be populated
# param 1: listener name
#
update_listener()
{
    local _listener="$1"
    local _wlspass="$(cat ${dir}/.keys/weblogic)"
    local _ovdtrustpass="$(cat ${dir}/.keys/bakeystore)"
    local _ovdidentpass="$(cat ${dir}/.keys/bakeystore)"
    
    local _wlst="connect('$WLS_USER','$_wlspass','t3://$ADMIN_HOST:$ADMIN_PORT')
configureSSL('$INSTANCE_NAME','$OVD_INSTANCE_NAME','ovd','$listener','$ovdprop')
custom()
cd('oracle.as.management.mbeans.register')
cd('oracle.as.management.mbeans.register:type=component,name=$OVD_INSTANCE_NAME,instance=$OVD_INSTANCE_NAME')
invoke('load',jarray.array([],java.lang.Object),jarray.array([],java.lang.String))
cd('../..')
cd('oracle.as.ovd')
cd('oracle.as.ovd:type=component.listenersconfig.sslconfig,name=$_listener,instance=$OVD_INSTANCE_NAME,component=ovd1')
set('KeyStorePassword',java.lang.String('$_ovdidentpass').toCharArray())
set('TrustStorePassword',java.lang.String('$_ovdtrustpass').toCharArray())
cd('../..')
cd('oracle.as.management.mbeans.register')
cd('oracle.as.management.mbeans.register:type=component,name=$OVD_INSTANCE_NAME,instance=$OVD_INSTANCE_NAME')
invoke('save',jarray.array([],java.lang.Object),jarray.array([],java.lang.String))
exit()
"
    echo "${_wlst}" | ${ORACLE_COMMON}/common/bin/wlst.sh
}


# update component registration. this needs to be executed after changes 
# in the admin gateway listener on the particular host
#
update_component_reg() 
{
    $INSTANCE_HOME/bin/opmnctl updatecomponentregistration \
        -adminHost $ADMIN_HOST \
        -adminPort $ADMIN_PORT \
        -adminUsername $WLS_USER \
        -adminPasswordFile ${dir}/.keys/weblogic \
        -componentType OVD \
        -componentName $OVD_INSTANCE_NAME
}


# main workflow ---------------------------------------------------------
#
create_keystores

show_keystores

# when started with parameter save the keyfiles there
if [ $# -gt 0 ]
then
    cp -rp "$wdir" "$1"
fi

update_keystore

echo "SSLEnabled=true"                     >$ovdprop
echo "AuthenticationType=Server"          >>$ovdprop
echo "SSLVersions=TLSv1,SSLv2Hello,SSLv3" >>$ovdprop
echo "KeyStore=$OVD_IDENT_NEW"            >>$ovdprop
echo "TrustStore=$OVD_TRUST_NEW"          >>$ovdprop

update_listener "LDAP SSL Endpoint"
update_listener "Admin Gateway"

opmnctl stopproc ias-component=$OVD_INSTANCE_NAME
opmnctl startroc ias-component=$OVD_INSTANCE_NAME

update_component_reg

echo "*** Completed"
