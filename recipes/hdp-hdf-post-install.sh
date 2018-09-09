#!/bin/bash

installUtils () {
	echo "*********************************Installing Tools..."
	yum install -y wget curl tar unzip
	
	echo "*********************************Installing Maven..."
	wget http://www-eu.apache.org/dist/maven/maven-3/3.5.4/binaries/apache-maven-3.5.4-bin.tar.gz -O /usr/local/apache-maven-3.5.4-bin.tar.gz
	tar xzf /usr/local/apache-maven-3.5.4-bin.tar.gz -C /usr/local
	ln -s /usr/local/apache-maven-3.5.4 /usr/local/maven
	cat >> /etc/profile.d/maven.sh <<ENDOF
export M2_HOME=/usr/local/maven
export PATH=$M2_HOME/bin:$PATH
ENDOF
	source /etc/profile.d/maven.sh
	
	echo "*********************************Installing GIT..."
	yum install -y git
	
	echo "*********************************Installing Docker..."
	echo " 				  *****************Installing Docker via Yum..."
    yum remove -y docker docker-common docker-selinux docker-engine-selinux docker-engine docker-ce
    yum install -y yum-utils device-mapper-persistent-data lvm2
	yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
	yum install -y docker-ce
	echo " 				  *****************Configuring Docker Permissions..."
	usermod -aG docker cloudbreak
	echo " 				  *****************Registering Docker to Start on Boot..."
	systemctl enable docker
	systemctl start docker
}

waitForAmbari () {
       	# Wait for Ambari
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
        TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep -Po 'OK')
        if [ "$TASKSTATUS" == OK ]; then
                LOOPESCAPE="true"
                TASKSTATUS="READY"
        else
               	AUTHSTATUS=$(curl -k -s -u $AMBARI_CREDS -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep HTTP | grep -Po '( [0-9]+)'| grep -Po '([0-9]+)')
               	if [ "$AUTHSTATUS" == 403 ]; then
               	echo "THE AMBARI PASSWORD IS NOT SET TO: admin"
               	echo "RUN COMMAND: ambari-admin-password-reset, SET PASSWORD: admin"
               	exit 403
               	else
                TASKSTATUS="PENDING"
               	fi
       	fi
       	echo "Waiting for Ambari..."
        echo "Ambari Status... " $TASKSTATUS
        sleep 2
       	done
}

serviceExists () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"status" : ' | grep -Po '([0-9]+)')

       	if [ "$SERVICE_STATUS" == 404 ]; then
       		echo 0
       	else
       		echo 1
       	fi
}

getServiceStatus () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')

       	echo $SERVICE_STATUS
}

waitForService () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
        until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

waitForServiceToStart () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED ]]; then
        	until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

stopService () {
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Stopping Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == STARTED ]; then
        TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Stop $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"INSTALLED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Stop $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [ "$TASKSTATUS" == COMPLETED ]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Stop $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
        echo "*********************************$SERVICE Service Stopped..."
       	elif [ "$SERVICE_STATUS" == INSTALLED ]; then
       	echo "*********************************$SERVICE Service Stopped..."
       	fi
}

startService (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Start $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"STARTED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [[ "$TASKSTATUS" == COMPLETED || "$TASKSTATUS" == FAILED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}

startServiceAndComplete (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"INSTALL COMPLETE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"STARTED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [[ "$TASKSTATUS" == COMPLETED || "$TASKSTATUS" == FAILED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}

installSchemaRegistryService () {
       	
       	echo "*********************************Creating REGISTRY service..."
       	# Create Schema Registry service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY

       	sleep 2
       	echo "*********************************Adding REGISTRY SERVER component..."
       	# Add REGISTRY SERVER component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY/components/REGISTRY_SERVER

       	sleep 2
       	echo "*********************************Creating REGISTRY configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME registry-common $ROOT_PATH/CloudBreakArtifacts/hdf-config/registry-config/registry-common.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME registry-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/registry-config/registry-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME registry-log4j $ROOT_PATH/CloudBreakArtifacts/hdf-config/registry-config/registry-log4j.json
		
       	echo "*********************************Adding REGISTRY SERVER role to Host..."
       	# Add REGISTRY_SERVER role to Ambari Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/REGISTRY_SERVER

       	sleep 30
       	echo "*********************************Installing REGISTRY Service"
       	# Install REGISTRY Service
       	TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Schema Registry"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Schema Registry"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/REGISTRY | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

installStreamlineService () {
       	
       	echo "*********************************Creating STREAMLINE service..."
       	# Create Streamline service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE

       	sleep 2
       	echo "*********************************Adding STREAMLINE SERVER component..."
       	# Add STREAMLINE SERVER component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE/components/STREAMLINE_SERVER

       	sleep 2
       	echo "*********************************Creating STREAMLINE configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME streamline-common $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME streamline-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME streamline-log4j $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-log4j.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME streamline_jaas_conf $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline_jaas_conf.json
		
       	echo "*********************************Adding STREAMLINE SERVER role to Host..."
       	# Add STREAMLINE SERVER role to Ambari Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/STREAMLINE_SERVER

       	sleep 30
       	echo "*********************************Installing STREAMLINE Service"
       	# Install STREAMLINE Service
       	TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install SAM"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install SAM"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/STREAMLINE | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
       	
		echo "********************************* Adding Symbolic Links to Atlas Client..."
		#Add symbolic links to Atlas Hooks
		rm -f /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
		rm -f /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar

		export ATLAS_PLUGIN_CLASSLOADER=$(ls -l /usr/hdp/current/atlas-client/hook/storm/atlas-plugin-classloader*|grep -Po 'atlas-plugin-classloader-[\D\d]+')
		export ATLAS_STORM_BRIDGE=$(ls -l /usr/hdp/current/atlas-client/hook/storm/storm-bridge-shim-*|grep -Po 'storm-bridge-shim-[\D\d]+')
		ln -s /usr/hdp/current/atlas-client/hook/storm/$ATLAS_PLUGIN_CLASSLOADER /usr/hdf/current/storm-client/lib/atlas-plugin-classloader.jar
		ln -s /usr/hdp/current/atlas-client/hook/storm/$ATLAS_STORM_BRIDGE /usr/hdf/current/storm-client/lib/storm-bridge-shim.jar
}

installNifiService () {
       	echo "*********************************Creating NIFI service..."
       	# Create NIFI service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI

       	sleep 2
       	echo "*********************************Adding NIFI MASTER component..."
       	# Add NIFI Master component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER
		curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_CA
		
       	sleep 2
       	echo "*********************************Creating NIFI configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-config $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-ssl-config $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-ssl-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-authorizers-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-authorizers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-notification-services-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-notification-services-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-flow-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-flow-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-login-identity-providers-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-login-identity-providers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-node-logback-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-node-logback-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-properties $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-properties.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-state-management-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-state-management-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-jaas-conf $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-jaas-conf.json
				
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME nifi-logsearch-conf $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-logsearch-conf.json
		
       	echo "*********************************Adding NIFI MASTER role to Host..."
       	# Add NIFI Master role to Ambari Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_MASTER

       	echo "*********************************Adding NIFI CA role to Host..."
		# Add NIFI CA role to Ambari Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_CA

       	sleep 30
       	echo "*********************************Installing NIFI Service"
       	# Install NIFI Service
       	TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}


waitForNifiServlet () {
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
       		TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller | grep -Po 'OK')
       		if [ "$TASKSTATUS" == OK ]; then
               		LOOPESCAPE="true"
       		else
               		TASKSTATUS="PENDING"
       		fi
       		echo "*********************************Waiting for NIFI Servlet..."
       		echo "*********************************NIFI Servlet Status... " $TASKSTATUS
       		sleep 2
       	done
}

installDruidService () {
       	
       	echo "*********************************Creating DRUID service..."
       	# Create Druid service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID

       	sleep 2
       	echo "*********************************Adding DRUID components..."
       	# Add DRUID BROKER component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_BROKER
		sleep 2
		# Add DRUID COORDINATOR component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_COORDINATOR
       	# Add DRUID HISTORICAL component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_HISTORICAL
       	# Add DRUID MIDDLEMANAGER component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_MIDDLEMANAGER
		# Add DRUID OVERLORD component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_OVERLORD
       	# Add DRUID ROUTER component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_ROUTER
       	# Add DRUID SUPERSET component to service
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID/components/DRUID_SUPERSET
		
       	sleep 2
       	echo "*********************************Creating DRUID configuration..."

       	# Create and apply configuration
       	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-broker $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-broker.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-common $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-common.json

		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-coordinator $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-coordinator.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-historical $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-historical.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-log4j $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-log4j.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-logrotate $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-logrotate.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-middlemanager $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-middlemanager.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-overlord $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-overlord.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-router $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-router.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-superset-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-superset-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME druid-superset $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-superset.json
		
		export HOST1=$(getHostByPosition 1)
		export HOST2=$(getHostByPosition 2)
		export HOST3=$(getHostByPosition 3)			
		
       	echo "*********************************Adding DRUID BROKER role to Host..."
       	# Add DRUID BROKER role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_BROKER
       	export DRUID_BROKER=$HOST1
       	
       	echo "*********************************Adding DRUID SUPERSET role to Host..."
       	# Add DRUID SUPERSET role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_SUPERSET
       	
       	echo "*********************************Adding DRUID ROUTER role to Host..."
       	# Add DRUID BROKER role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_ROUTER
       	
       	echo "*********************************Adding DRUID OVERLORD role to Host..."
       	# Add DRUID OVERLORD role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_OVERLORD
       	
       	echo "*********************************Adding DRUID COORDINATOR role to Host..."
       	# Add DRUID COORDINATOR role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DRUID_COORDINATOR
       	
       	echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_HISTORICAL
		
		echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_HISTORICAL
       	
       	echo "*********************************Adding DRUID HISTORICAL role to Host..."
       	# Add DRUID HISTORICAL role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST3/host_components/DRUID_HISTORICAL
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST1/host_components/DRUID_MIDDLEMANAGER
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST2/host_components/DRUID_MIDDLEMANAGER
       	
       	echo "*********************************Adding DRUID MIDDLEMANAGER role to Host..."
       	# Add DRUID MIDDLEMANAGER role to Host
       	curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$HOST3/host_components/DRUID_MIDDLEMANAGER

       	sleep 30
       	echo "*********************************Installing DRUID Service"
       	# Install DRUID Service
       	TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Druid"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -k -s -u $AMBARI_CREDS -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Druid"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DRUID | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

installHDFManagementPack () {
	wget http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.1.1/tars/hdf_ambari_mp/hdf-ambari-mpack-3.0.1.1-5.tar.gz
	ambari-server install-mpack --mpack=hdf-ambari-mpack-3.0.1.1-5.tar.gz --verbose

	sleep 2
	ambari-server restart
	waitForAmbari
	sleep 2
}

getHostByPosition (){
	HOST_POSITION=$1
	HOST_NAME=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts|grep -Po '"host_name" : "[a-zA-Z0-9_\W]+'|grep -Po ' : "([^"]+)'|grep -Po '[^: "]+'|tail -n +$HOST_POSITION|head -1)
	
	echo $HOST_NAME
}

enablePhoenix () {
	echo "*********************************Enabling Phoenix..."
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME hbase-site phoenix.functions.allowUserDefinedFunctions true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.defaults.for.version.skip true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.regionserver.wal.codec org.apache.hadoop.hbase.regionserver.wal.IndexedWALEditCodec
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.region.server.rpc.scheduler.factory.class org.apache.hadoop.hbase.ipc.PhoenixRpcSchedulerFactory
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.rpc.controllerfactory.class org.apache.hadoop.hbase.ipc.controller.ServerRpcControllerFactory
}

fixStorm () {
	echo "*********************************Fixing Storm..."
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME storm-env storm.atlas.hook false
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME storm-site nimbus.childopts "-Xmx1024m _JAAS_PLACEHOLDER"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh -u $USERID -p $PASSWD set $AMBARI_HOST $CLUSTER_NAME storm-site supervisor.childopts "-Xmx256m _JAAS_PLACEHOLDER -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.port={{jmxremote_port}}"
}



export ROOT_PATH=~
echo "*********************************ROOT PATH IS: $ROOT_PATH"

export AMBARI_HOST=$(hostname -f)
echo "*********************************AMABRI HOST IS: $AMBARI_HOST"

export $AMBARI_CREDS=$USERID:$PASSWD
export CLUSTER_NAME=$(curl -k -s -u $AMBARI_CREDS -X GET http://$AMBARI_HOST:8080/api/v1/clusters |grep cluster_name|grep -Po ': "(.+)'|grep -Po '[a-zA-Z0-9\-_!?.]+')

if [[ -z $CLUSTER_NAME ]]; then
        echo "Could not connect to Ambari Server. Please run the install script on the same host where Ambari Server is installed."
        exit 0
else
       	echo "*********************************CLUSTER NAME IS: $CLUSTER_NAME"
fi

export HADOOP_USER_NAME=hdfs
echo "*********************************HADOOP_USER_NAME set to HDFS"

echo "*********************************Waiting for cluster install to complete..."
waitForServiceToStart YARN

waitForServiceToStart HDFS

waitForServiceToStart HIVE

waitForServiceToStart ZOOKEEPER

sleep 10

export VERSION=`hdp-select status hadoop-client | sed 's/hadoop-client - \([0-9]\.[0-9]\).*/\1/'`
export INTVERSION=$(echo $VERSION*10 | bc | grep -Po '([0-9][0-9])')
echo "*********************************HDP VERSION IS: $VERSION"

sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/registry-config/registry-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{registry_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{superset_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/streamline-config/streamline-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-common.json
sed -r -i 's;\{\{mysql_host\}\};'$AMBARI_HOST';' $ROOT_PATH/CloudBreakArtifacts/hdf-config/druid-config/druid-superset.json

echo "*********************************Install HDF Management Pack..."
installHDFManagementPack 

echo "*********************************Install Utilities..."
installUtils
sleep 2

echo "********************************* Enabling Phoenix"
enablePhoenix
echo "********************************* Restarting Hbase"
stopService HBASE
sleep 2
startService HBASE
sleep 2

echo "********************************* Fix Storm"
fixStorm
echo "********************************* Restarting Storm"
stopService STORM
sleep 2
startService STORM
sleep 2

installDruidService
sleep 2
DRUID_STATUS=$(getServiceStatus DRUID)
echo "*********************************Checking DRUID status..."
if ! [[ $DRUID_STATUS == STARTED || $DRUID_STATUS == INSTALLED ]]; then
       	echo "*********************************DRUID is in a transitional state, waiting..."
       	waitForService DRUID
       	echo "*********************************DRUID has entered a ready state..."
fi
sleep 2
if [[ $DRUID_STATUS == INSTALLED ]]; then
       	startService DRUID
else
       	echo "*********************************DRUID Service Started..."
fi
sleep 2

installSchemaRegistryService
sleep 2
REGISTRY_STATUS=$(getServiceStatus REGISTRY)
echo "*********************************Checking REGISTRY status..."
if ! [[ $REGISTRY_STATUS == STARTED || $REGISTRY_STATUS == INSTALLED ]]; then
       	echo "*********************************REGISTRY is in a transitional state, waiting..."
       	waitForService REGISTRY
       	echo "*********************************REGISTRY has entered a ready state..."
fi
sleep 2
if [[ $REGISTRY_STATUS == INSTALLED ]]; then
       	startService REGISTRY
else
       	echo "*********************************REGISTRY Service Started..."
fi
sleep 2

installStreamlineService
sleep 2
STREAMLINE_STATUS=$(getServiceStatus STREAMLINE)
echo "*********************************Checking STREAMLINE status..."
if ! [[ $STREAMLINE_STATUS == STARTED || $STREAMLINE_STATUS == INSTALLED ]]; then
       	echo "*********************************STREAMLINE is in a transitional state, waiting..."
       	waitForService STREAMLINE
       	echo "*********************************STREAMLINE has entered a ready state..."
fi
sleep 2
if [[ $STREAMLINE_STATUS == INSTALLED ]]; then
       	startService STREAMLINE
else
       	echo "*********************************STREAMLINE Service Started..."
fi
sleep 2

installNifiService
sleep 2
NIFI_STATUS=$(getServiceStatus NIFI)
echo "*********************************Checking NIFI status..."
if ! [[ $NIFI_STATUS == STARTED || $NIFI_STATUS == INSTALLED ]]; then
       	echo "*********************************NIFI is in a transitional state, waiting..."
       	waitForService NIFI
       	echo "*********************************NIFI has entered a ready state..."
fi
sleep 2
if [[ $NIFI_STATUS == INSTALLED ]]; then
       	startServiceAndComplete NIFI
else
       	echo "*********************************NIFI Service Started..."
fi
sleep 2

exit 0
