#!/usr/bin/env bash

if [[ $1 == "--config" ]] ; then
	cat <<EOF
configVersion: v1
onStartup: 5
kubernetes:
- name: OnCreateModifiedIngress
  apiVersion: extensions/v1beta1
  kind: Ingress
  executeHookOnEvent:
  - Added
  - Modified
  jqFilter: .spec.rules[].host
- name: OnDeletedIngress
  apiVersion: extensions/v1beta1
  kind: Ingress
  executeHookOnEvent:
  - Deleted
  jqFilter: .spec.rules[].host
##  jqFilter: ".metadata.labels"
EOF
else
	echo START
	bindingName=$(jq -r '.[0].binding' $BINDING_CONTEXT_PATH)

	if [[ $bindingName == "onStartup" ]] ; then
		echo "ingress-hook is triggered on startup."
	
		mkdir -p $SHELL_OPERATOR_TMP_DIR/{domains,bindings}   # Store all managed domain infos here and bindings

		# For debug FIXME
		cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$bindingName

		exit 0
	fi

	#cat $BINDING_CONTEXT_PATH | jq .[].object.metadata.name

	# ignore Synchronization for simplicity
	type=$(jq -r '.[0].type' $BINDING_CONTEXT_PATH)
	if [[ $type == "Synchronization" ]] ; then
		echo Got Synchronization event

		cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$resourceName.$bindingName.$type

		exit 0
	fi

	resourceEvent=$(jq -r '.[0].watchEvent' $BINDING_CONTEXT_PATH)
	resourceName=$(jq -r '.[0].object.metadata.name' $BINDING_CONTEXT_PATH)

	# For debug FIXME
	cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$resourceName.$bindingName.$resourceEvent

	echo "EVENT => [[[resourceName=$resourceName  resourceEvent=$resourceEvent]]]"

	echo "Ingress $resourceName host was $resourceEvent"

	# Fetch all the host fields from the object
	hosts=$(jq -r ".[].object.spec.rules[].host" $BINDING_CONTEXT_PATH)
	[ "$hosts" = "null" ] && echo "No host field found in ingress/$resourceName" && exit 0

	for host in $hosts
	do
		#host=$(jq -r ".[0].object.spec.rules[0].host" $BINDING_CONTEXT_PATH)
		echo Processing host=$host

		hostedZoneName=
		# Detect which zone this host belongs to...
		#zoneDir=$SHELL_OPERATOR_TMP_DIR/domains/
		for f in `ls $SHELL_OPERATOR_TMP_DIR/domains`
		do
			echo f=$f
			#zone=`echo $f | cut -d. -f2-`
			zone=`basename $f`
			echo "trying zone $zone"
			echo $host | grep "$zone$" && hostedZoneName=$zone && break
		done
		[ ! "$hostedZoneName" ] && echo "No domain matched for $host" && exit 0

		zoneDir=$SHELL_OPERATOR_TMP_DIR/domains/$zone
		mkdir -p $zoneDir/hosts

		echo # DEBUG ########
		echo ls -1 $zoneDir $zoneDir/hosts
		ls -1 $zoneDir $zoneDir/hosts
		echo # DEBUG ########

		[ ! -s $zoneDir/zoneId ] && echo File missing ... aborting && exit 0
		[ ! -s $zoneDir/appsEndpoint ] && echo File missing ... aborting && exit 0
		[ ! -s $zoneDir/recordType ] && echo File missing ... aborting && exit 0
		zoneId=`cat $zoneDir/zoneId`
		appsEndpoint=`cat $zoneDir/appsEndpoint`
		recordType=`cat $zoneDir/recordType`

		if [[ $bindingName == "OnCreateModifiedIngress" ]] ; then
			echo "Ingress $resourceName was $resourceEvent for virtual host $host"

			if [ ! -s $zoneDir/hosts/$host ] ; then 
				echo record_add.sh --action UPSERT --type $recordType --fqdn $host --target $appsEndpoint --zone-id $zoneId --id "Managed by $0"
				record_add.sh      --action UPSERT --type $recordType --fqdn $host --target $appsEndpoint --zone-id $zoneId --id "Managed by $0" && echo $host > $zoneDir/hosts/$host 
			else
				echo Host $host already exists
			fi
		elif [[ $bindingName == "OnDeletedIngress" ]] ; then
			echo "Ingress $resourceName was $resourceEvent for virtual host $host"

			if [ -s $zoneDir/hosts/$host ] ; then 
				echo record_add.sh --action DELETE --type $recordType --fqdn $host --target $appsEndpoint --zone-id $zoneId --id "Managed by $0"
				record_add.sh      --action DELETE --type $recordType --fqdn $host --target $appsEndpoint --zone-id $zoneId --id "Managed by $0" && rm -f $zoneDir/hosts/$host 
				rmdir $zoneDir 2>/dev/null || true
			else
				echo Host $host does not exist
			fi
		else 
			echo "Unknown binding name [$bindingName]" >&2
		fi
	done

	exit 0
fi

