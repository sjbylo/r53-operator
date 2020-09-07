#!/bin/bash 
# Create a new A record

MY_TTL=60
MY_ACTION=UPSERT
MY_TYPE=A
MY_TARGET=127.0.0.1
MY_IDENTIFIER="Created by `basename $0`"

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -a|--action)
    MY_ACTION="$2"; shift ; shift
    ;;
    -f|--fqdn)
    MY_FQDN="$2"; shift ; shift
    ;;
    -t|--type)
    MY_TYPE="$2"; shift ; shift
    ;;
    -g|--target)
    MY_TARGET="$2"; shift ; shift
    ;;
    -l|--ttl)
    MY_TTL="$2"; shift ; shift
    ;;
    -z|--zone-id)
    MY_HOSTED_ZONE="$2"; shift ; shift
    ;;
    -i|--id)
    MY_IDENTIFIER="$2"; shift ; shift
    ;;
    *) 
    echo "Unknown option $key"
    exit 1
    ;;
esac
done
#[ "$@" ] && MY_IDENTIFIER="$@"
#set -- "${POSITIONAL[@]}" # restore positional parameters

#echo "MY_ACTION  = ${MY_ACTION}"
#echo "MY_FQDN    = ${MY_FQDN}"
#echo "MY_TYPE    = ${MY_TYPE}"
#echo "MY_TARGET  = ${MY_TARGET}"
#echo "MY_HOSTED_ZONE  = ${MY_HOSTED_ZONE}"
#echo "MY_IDENTIFIER  = ${MY_IDENTIFIER}"
##echo "POSITIONAL     = ${POSITIONAL[@]}"

# Create A record

cat <<END > /tmp/$MY_FQDN.$MY_ACTION.json
{
    "Changes": [
        {
            "Action": "$MY_ACTION",
            "ResourceRecordSet": {
                "Name": "$MY_FQDN",
                "ResourceRecords": [
                    {
                        "Value": "$MY_TARGET"
                    }
                ],
                "TTL": $MY_TTL,
                "Type": "$MY_TYPE"
            }
        }
    ],
    "Comment": "CREATE/DELETE/UPSERT a record "
}
END

aws route53 change-resource-record-sets --hosted-zone-id $MY_HOSTED_ZONE --change-batch file:///tmp/$MY_FQDN.$MY_ACTION.json


