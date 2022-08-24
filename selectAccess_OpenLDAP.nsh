#!/bin/nsh
# ©2008 Frank Lamprea, BladeLogic.
#
# Script that will create LDAP registraton for HP SelectAccess IIS Enforcer Agents
#
# This should be added as a CENTRALLY EXECUTED 
#

#Arguments:
#        -i     LDAP Property Instance
#        -p     Path to OpenLDAP (NSH)
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
#OPENLDAP_PATH_NSH="/C/OpenLDAP"
OPENLDAP_PATH_NSH="${OP}"
print_debug "OPENLDAP_PATH_NSH=$OPENLDAP_PATH_NSH"
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
	echo "INFO: ldapServer --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} ldapServer"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" ldapServer
	check_errs $? "BLCLI FAILED"
	blcli_storeenv LDAPSERVER
	echo " "

	echo "INFO: ldapUser --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} ldapUser"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" ldapUser
	check_errs $? "BLCLI FAILED"
	blcli_storeenv LDAPUSER
	echo " "

	echo "INFO: ldapPassword --->"
	print_debug "blcli_execute PropertyInstance getPropertyValue Class://SystemObject/SelectAccess/LDAP/${OI} ldapPassword"
	blcli_execute PropertyInstance getPropertyValue "Class://SystemObject/SelectAccess/LDAP/${OI}" ldapPassword
	check_errs $? "BLCLI FAILED"
	blcli_storeenv LDAPPASSWORD
	echo " "

	# Test to see if the Ceridian / OpenLDAP directory is present
	echo "INFO: Validating Directory... --->"
	if [ -d "$OPENLDAP_PATH_NSH/Ceridian" ]
	then
		echo "INFO: Directory Found --->"
	else 
	    echo "ERROR: $OPENLDAP_PATH_NSH/Ceridian does not Exist --->"
	    exit 1
	fi

	# Retrieve the Custom ldapAdd.conf from the target server.
	# This file has embedded information that is unique for each client server
	echo "INFO: Retrieving ldapAdd.conf from $HOST --->"
	cd $OPENLDAP_PATH_NSH
	check_errs $? "CHANGE DIR FAILED"
	rm -f ./Ceridian/ldapAdd.conf
	cp -v //$HOST/c/OpenLDAP/Ceridian/ldapAdd.conf ./Ceridian
	check_errs $? "COPY COMMAND FAILED"
		
	#Step 2: Create the LDAP Record
		
	echo "INFO: Creating the LDAP Record on $LDAPSERVER --->"
	cd $OPENLDAP_PATH_NSH
	print_debug "./ldapmodify -a -f ./Ceridian/ldapAdd.conf -h $LDAPSERVER -x -w $LDAPPASSWORD -D $LDAPUSER"
	RESULT=`./ldapmodify -a -f ./Ceridian/ldapAdd.conf -h "$LDAPSERVER" -x -w "$LDAPPASSWORD" -D "$LDAPUSER"`
	check_errs $? "OPENLDAP FAILED"
	print_debug "$RESULT"

	# Clean up temporary files
	echo "INFO: Removing Temp Files --->"
	cd $OPENLDAP_PATH_NSH
	rm -f "./Ceridian/ldapAdd.conf"
	
done

echo "INFO: Disconnect BLCLI... --->"
blcli_destroy
exit 0