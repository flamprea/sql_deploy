#!/bin/nsh
# ©2008 Frank Lamprea, BladeLogic.
#
# Script that will create SSL certificates for HP SelectAccess IIS Enforcer Agents
#
# This should be added as a CENTRALLY EXECUTED 
#

#Arguments:
#        -i     LDAP Property Instance
#        -p     Path to OpenSSL (NSH)
#	-h      List of hosts
#	-d	Debug <0|1>


while [ $# -gt 0 ]
	do
	case "${1}" in
	-i)
		shift
		OI="${1}"
		;;
	-p)
		shift
		OP="${1}"
		;;
	-h)
		shift
		OH="${1}"
		;;
	-d)
		shift
		OD="${1}"
		;;

	*)
		echo "ERROR: bad argument, ${1}"
		exit 1
		;;
	esac
	shift
done

# Define Subroutines
check_errs()
{
  # Function. Parameter 1 is the return code
  # Para. 2 is text to display on failure.
  if [ "${1}" -ne "0" ]; then
    echo "ERROR # ${1} : ${2}"
    # as a bonus, make our script exit with the right error code.
    exit ${1}
  fi
}

print_debug()
{
  # Function. Parameter 1 is the message
  if [ "${OD}" -ne "0" ]; then
    echo "DEBUG: ${1}"    
  fi
}

# Define Vars
#OPENSSL_PATH_WIN="C:\OpenSSL\bin"
#OPENSSL_PATH_NSH="/C/OpenSSL/bin"
OPENSSL_PATH_NSH="${OP}"
print_debug "OPENSSL_PATH_NSH=$OPENSSL_PATH_NSH"
HOST_LIST="${OH}"
print_debug "HOST_LIST=$HOST_LIST"

# Initialize BLCLI 
echo "INFO: Initialize BLCLI... --->"
blcli_connect
check_errs $? "Failed to Initialize BLCLI"


for HOST in ${HOST_LIST[@]}
do
	
	echo "INFO: Collecting Properties for $HOST --->"
	
	# Collect Property Information
	echo "INFO: distinguishedNameSuffix --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} distinguishedNameSuffix"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" distinguishedNameSuffix
	check_errs $? "BLCLI FAILED"
	blcli_storeenv DNSUFFIX
	#echo "$DNSUFFIX"
	echo " "

	echo "INFO: distinguishedNameOpenSSLPrefix --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} distinguishedNameOpenSSLPrefix"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" distinguishedNameOpenSSLPrefix
	check_errs $? "BLCLI FAILED"
	blcli_storeenv DNSSLPREFIX
	#echo "$DNSSLPREFIX"
	echo " "

	echo "INFO: commonNameSuffix --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} commonNameSuffix"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" commonNameSuffix
	check_errs $? "BLCLI FAILED"
	blcli_storeenv CNSUFFIX
	#echo "$CNSUFFIX"
	echo " "

	echo "INFO: FQDN --->"
	print_debug "blcli_execute Server printPropertyValue $HOST FQ_HOST"
	blcli_execute Server printPropertyValue $HOST FQ_HOST
	check_errs $? "BLCLI FAILED"
	blcli_storeenv FQDN
	#echo "$FQDN"
	echo " "

	# Test to see if the Ceridian / OpenSSL directory is present
	echo "INFO: Validating Directory... --->"
	if [ -d "$OPENSSL_PATH_NSH/Ceridian" ]
	then
		echo "INFO: Directory Found --->"
	else 
	    echo "ERROR: $OPENSSL_PATH_NSH/Ceridian does not Exist --->"
	    exit 1
	fi

	# Retrieve the Custom openssl.cnf from the target server.
	# This file has embedded information that is unique for each client server
	#Step 1: Edit the openssl.cnf file to include the relevant updates for your environment. Collect the Enforcer configuration location DN from LDAP.
	echo "INFO: Retrieving openssl.cnf from $HOST --->"
	cd $OPENSSL_PATH_NSH
	check_errs $? "CHANGE DIR FAILED"
	rm -f ./Ceridian/openssl.cnf
	cp //$HOST/c/OpenSSL/bin/Ceridian/openssl.cnf ./Ceridian
	check_errs $? "COPY COMMAND FAILED"
		
	#Step 2: Create the Client Key and Request
	#- mykey.pem is the new Enforcer's private key, and req.pem is the PKCS#10 certificate request file
	
	echo "INFO: Creating the Client Key and Request --->"
	cd $OPENSSL_PATH_NSH
	RESULT=`./openssl req -nodes -newkey rsa:1024 -keyout "./Ceridian/mykey.pem" -out "./Ceridian/req.pem" -config "./Ceridian/openssl.cnf"`
	check_errs $? "OPENSSL FAILED"
	print_debug "$RESULT"

	#Step 4: Sign the request with the Server CA Key
	#- openssl.cnf is the configuration file. 
	#- req.pem is the PKCS#10 certificate request. 
	#- mycert.pem is the signed certificate output
	#- the -subj line is used to create the proper subject. Use '/' at the beginning and in
	#  place of commas. Don't use spaces.
	#- The keyfile is the Private Key for the Select Access Administration Server - decrypted 
	#  manually and placed on the Appserver during install time

	echo "INFO: Signing the request with the Server CA Key --->"
	cd $OPENSSL_PATH_NSH
	RESULT=`./openssl ca -batch -config "./Ceridian/openssl.cnf" -in "./Ceridian/req.pem" -out "./Ceridian/mycert.pem" -keyfile "./Ceridian/selectAccess.rsa.privateCA.der" -preserveDN -extensions sa_extensions -subj ${DNSSLPREFIX}CN=${FQDN}:${CNSUFFIX}`
	check_errs $? "OPENSSL FAILED"
	print_debug "$RESULT"

	#Step 5: Remove encryption from Private Key
	#- The private key is unencrypted in the enforcer configuration file, but it is PEM encoded

	echo "INFO: Removing encryption from the Private Key --->"
	cd $OPENSSL_PATH_NSH
	RESULT=`./openssl rsa -in "./Ceridian/mykey.pem" -out "./Ceridian/mykey-ne.pem"`
	check_errs $? "OPENSSL FAILED"
	print_debug "$RESULT"
	
	# Find location of the certificate
	echo "INFO: Locating SSL Certificate Position --->"
	cd $OPENSSL_PATH_NSH
	CERT_POSITION=`cat "./Ceridian/mycert.pem" | grep -n '\-----BEGIN' | grep -v grep | cut -d ':' -f1`
	check_errs $? "OPENSSL FAILED"
	print_debug "$CERT_POSITION"

	# Extract Certificate
	echo "INFO: Extracting SSL Certificate --->"
	CERTIFICATE=`tail +$CERT_POSITION "./Ceridian/mycert.pem"`
	check_errs $? "OPENSSL FAILED"
	print_debug "$CERTIFICATE"
	
	# Inject Certificate into Server Property
	#echo "INFO: Uploading Certificate to Server Property --->"
	#print_debug "blcli_execute Server setPropertyValueByName $HOST IIS_ENFORCER_SSLCERT $CERTIFICATE"
	#blcli_execute Server setPropertyValueByName $HOST IIS_ENFORCER_SSLCERT "$CERTIFICATE"
	#check_errs $? "BLCLI FAILED"
	#blcli_storeenv RESULT
	#print_debug "$RESULT"
	#echo " "

	# Find location of the key
	echo "INFO: Locating SSL Key Position --->"
	cd $OPENSSL_PATH_NSH
	KEY_POSITION=`cat "./Ceridian/mykey-ne.pem" | grep -n '\-----BEGIN' | grep -v grep | cut -d ':' -f1`
	check_errs $? "OPENSSL FAILED"
	print_debug "$KEY_POSITION"

	# Extract Certificate
	echo "INFO: Extracting SSL Key --->"
	KEY=`tail +$KEY_POSITION "./Ceridian/mykey-ne.pem"`
	check_errs $? "OPENSSL FAILED"
	print_debug "$KEY"
	
	# Inject Certificate into Server Property
	#echo "INFO: Uploading Key to Server Property --->"
	#print_debug "blcli_execute Server setPropertyValueByName $HOST IIS_ENFORCER_SSLKEY $KEY"
	#blcli_execute Server setPropertyValueByName $HOST IIS_ENFORCER_SSLKEY "$KEY"
	#check_errs $? "BLCLI FAILED"
	#blcli_storeenv RESULT
	#print_debug "$RESULT"
	#echo " "
	
	echo "INFO: Retrieving Server CA Certificate --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/enforcerIIS/${OI} serverCertCA"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/enforcerIIS/${OI}" serverCertCA
	check_errs $? "BLCLI FAILED"
	blcli_storeenv CACERT
	#echo "$CACERT"
	echo " "
	
	echo "INFO: Retrieving File Parts --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/enforcerIIS/${OI} enforcerFile_1"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/enforcerIIS/${OI}" enforcerFile_1
	check_errs $? "BLCLI FAILED"
	blcli_storeenv EF1
	echo " "
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/enforcerIIS/${OI} enforcerFile_2"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/enforcerIIS/${OI}" enforcerFile_2
	check_errs $? "BLCLI FAILED"
	blcli_storeenv EF2
	echo " "
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/enforcerIIS/${OI} enforcerFile_3"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/enforcerIIS/${OI}" enforcerFile_3
	check_errs $? "BLCLI FAILED"
	blcli_storeenv EF3
	echo " "
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/enforcerIIS/${OI} enforcerFile_4"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/enforcerIIS/${OI}" enforcerFile_4
	check_errs $? "BLCLI FAILED"
	blcli_storeenv EF4
	echo " "
	
	# Build the File
	echo "INFO: Building enforcer_iis.xml on $HOST --->"
	echo "${EF1}${CERTIFICATE}${EF2}${KEY}${EF3}${CACERT}${EF4}" > //$HOST/c/Program\ Files/HP\ OpenView/Select\ Access/bin/enforcer_iis.xml
	check_errs $? "FILE CONTRUCT FAILED"
	
	# Clean up temporary files
	echo "INFO: Removing Temp Files --->"
	cd $OPENSSL_PATH_NSH
	rm -f "./Ceridian/mykey-ne.pem"
	rm -f "./Ceridian/mykey.pem"
	rm -f "./Ceridian/mycert.pem"
	rm -f "./Ceridian/req.pem"
	
done

echo "INFO: Disconnect BLCLI... --->"
blcli_destroy
exit 0

