#!/usr/bin/env bash

if [[ $1 == "--config" ]] ; then
	cat <<EOF
configVersion: v1
onStartup: 5
kubernetes:
- name: OnCreatedModifiedCustomDomain
  apiVersion: stable.example.com/v1
  kind: CustomDomain
  executeHookOnEvent:
  - Added
  - Modified
  jqFilter: ".spec"
- name: OnDeletedCustomDomain
  apiVersion: stable.example.com/v1
  kind: CustomDomain
  executeHookOnEvent:
  - Deleted
EOF
else
	bindingName=$(jq -r '.[0].binding' $BINDING_CONTEXT_PATH)
	resourceEvent=$(jq -r '.[0].watchEvent' $BINDING_CONTEXT_PATH)
	resourceName=$(jq -r '.[0].object.metadata.name' $BINDING_CONTEXT_PATH)

	if [[ $bindingName == "onStartup" ]] ; then
		echo "customdomain-hook is triggered on startup."

		# FIXME rm -rf $SHELL_OPERATOR_TMP_DIR/*
		mkdir -p $SHELL_OPERATOR_TMP_DIR/{domains,bindings}   # Store all managed domain infos here and bindings

		# For debug FIXME
		cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$bindingName

		## FIXME hostedZoneName=$(jq -r ".[0].object.spec.hostedZoneName" $BINDING_CONTEXT_PATH)
		echo "CR configuration:"
		ls -1 $SHELL_OPERATOR_TMP_DIR/$hostedZoneName

		exit 0
	fi

	#cat $BINDING_CONTEXT_PATH | jq .[].object.metadata.name

	# ignore Synchronization for simplicity
	type=$(jq -r '.[0].type' $BINDING_CONTEXT_PATH)
	if [[ $type == "Synchronization" ]] ; then
		echo Got Synchronization event

		# For debug FIXME
		cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$resourceName.$bindingName.$type

		exit 0
	fi

	# For debug FIXME
	cat $BINDING_CONTEXT_PATH > $SHELL_OPERATOR_TMP_DIR/bindings/$resourceName.$bindingName.$resourceEvent

	echo "EVENT => [[[resourceName=$resourceName  resourceEvent=$resourceEvent]]]"

	if [[ $bindingName == "OnCreatedModifiedCustomDomain" ]] ; then
		umask 077

		# The CR can suply the aws credentials unless they can be found in the local kube cluster

		# Attempt to fetch the cloud credentials 
		#kubectl get secrets aws-cloud-credentials -n openshift-machine-api -o json | jq 'del(.metadata.managedFields,.metadata.annotations,.metadata.selfLink)' | kubectl apply -f -

		cloudCredentialsSecret=$(jq -r ".[0].object.spec.secret" $BINDING_CONTEXT_PATH)

		awsAccessKeyId=$(kubectl get secrets $cloudCredentialsSecret -o json | jq -r .data.aws_access_key_id | base64 --decode)
		awsSecretAccessKey=$(kubectl get secrets $cloudCredentialsSecret -o json | jq -r .data.aws_secret_access_key | base64 --decode)

			# DEBUG FIXME
			mkdir -p ~/.aws2
			cat > ~/.aws2/credentials <<-END
			[default]
			aws_access_key_id = $awsAccessKeyId
			aws_secret_access_key = $awsSecretAccessKey
			END
			# DEBUG

		touch ~/.aws/credentials

		# Set up the aws cli credentials if they don't already exist
		if ! grep -q "^aws_access_key_id = $awsAccessKeyId$" ~/.aws/credentials
		then
			mkdir -p ~/.aws
			cat >> ~/.aws/credentials <<-END
			[default]
			aws_access_key_id = $awsAccessKeyId
			aws_secret_access_key = $awsSecretAccessKey
			END
		fi

		# The CR must define either one or both of zone id and/or hosted zone name
		zoneId=$(jq -r ".[0].object.spec.zoneId" $BINDING_CONTEXT_PATH)
		hostedZoneName=$(jq -r ".[0].object.spec.hostedZoneName" $BINDING_CONTEXT_PATH)

		echo "zoneId=$zoneId hostedZoneName=$hostedZoneName"

		if [ "$zoneId" = "null"  -a "$hostedZoneName" ] ; then
			zoneId=$(aws route53 list-hosted-zones-by-name --dns-name $hostedZoneName | jq -r '.HostedZones[0].Id' | cut -d/ -f3)
		elif [ "$hostedZoneName" = "null" -a "$zoneId" ] ; then
			hostedZoneName=$(aws route53 list-hosted-zones | jq -r '.HostedZones[].Name' | sort | head -1)
			hostedZoneName=$(echo $hostedZoneName | sed 's/\.$//')  # Remove the '.'
		elif [ "$hostedZoneName" = "null" -a "$zoneId" = "null" ] ; then
			echo "Provide at least a route53 hosted zone ID and/or a hosted zone domain name" >&2
			exit 0
		fi

		echo "CustomDomain $resourceName was $resourceEvent"

		appsEndpoint=$(jq -r ".[0].object.spec.appsEndpoint" $BINDING_CONTEXT_PATH)

		# appsEndpoint is the VIP or hostname (CNAME) of the external public ingress endpoint (e.g. LB endpoint). Can be IP or FQDN
		if [ "$appsEndpoint" != "null" ] ; then
			echo "Using endpoint from spec"
		else
			# Try to fetch the router endpoint (fetches the ELB hostname if in AWS) 
			appsEndpoint=$(kubectl get svc --all-namespaces --selector=router=router-default -o jsonpath='{.items[].status.loadBalancer.ingress[0].hostname}{"\n"}') 
			echo "Discovered endpoint from router-default service"
		fi

		# Determine the record type needed
		echo appsEndpoint=$appsEndpoint
		if echo $appsEndpoint | egrep '^(([a-zA-Z](-?[a-zA-Z0-9])*)\.)+[a-zA-Z]{2,}$' ; then 
			echo Found endpoint domain name: $appsEndpoint
			recordType=CNAME
		elif echo $appsEndpoint | grep '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' ; then
			echo Found endpoint ip address: $appsEndpoint
			recordType=A
		else
			echo "Unknown record  type (either CNAME or A record)" >&2
			echo "Please include (or fix) it in the CR at spec.appsEndpoint" >&2
			exit 0
		fi

		echo = DEBUG ======================
		echo awsAccessKeyId=$awsAccessKeyId
		echo awsSecretAccessKey=$awsSecretAccessKey
		echo appsEndpoint=$appsEndpoint
		echo zoneId=$zoneId
		echo hostedZoneName=$hostedZoneName
		echo recordType=$recordType
		echo = DEBUG ======================

		[ ! "$appsEndpoint" ] && echo "appsEndpoint missing!" && exit 1
		[ ! "$awsAccessKeyId" ] && echo "awsAccessKeyId missing!" && exit 1
		[ ! "$awsSecretAccessKey" ] && echo "awsSecretAccessKey missing!" && exit 1
		[ ! "$zoneId" ] && echo "zoneId missing!" && exit 1
		[ ! "$hostedZoneName" ] && echo "hostedZoneName missing!" && exit 1
		[ ! "$recordType" ] && echo "recordType missing!" && exit 1

		# Store the configuration for the other hook(s)
		zoneDir=$SHELL_OPERATOR_TMP_DIR/domains/$hostedZoneName
		#mkdir -p $zoneDir/hosts
		mkdir -p $zoneDir
		echo $appsEndpoint 	> $zoneDir/appsEndpoint
		echo $zoneId 		> $zoneDir/zoneId
		echo $hostedZoneName 	> $zoneDir/hostedZoneName
		echo $recordType 	> $zoneDir/recordType

 		if [[ $resourceEvent == "Added" ]] ; then
			echo "Adding status into customdomain/$resourceName"
			kubectl patch customdomain $resourceName --type=json -p '[{"op": "replace", "path": "/status", "value": {}}]'
		fi
		echo "Adding status message into customdomain/$resourceName"
		kubectl patch customdomain $resourceName --type=json -p '[{"op": "replace", "path": "/status", "value": {}}]'
		kubectl patch customdomain $resourceName --type=json \
			-p '[{"op": "replace", "path": "/status/message", "value": "appsEndpoint='$appsEndpoint' zoneId='$zoneId' hostedZoneName='$hostedZoneName'"}]'

	elif [[ $bindingName == "OnDeletedCustomDomain" ]] ; then
		echo "CustomDomain $resourceName was deleted"

		hostedZoneName=$(jq -r ".[0].object.spec.hostedZoneName" $BINDING_CONTEXT_PATH)

		# FIXME do not delete if in test mode
		rm -vrf $zoneDir
		#rm -vrf $zoneDir $HOME/.aws 
	fi
 
	exit 0
fi

