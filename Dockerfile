#FROM registry.access.redhat.com/rhel8/go-toolset
FROM flant/shell-operator:latest

#RUN apt-get update
#RUN apt-get -qq install -y curl unzip

RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        python3-setuptools \
        groff \
	curl \
	unzip \
        less \
    && pip3 install --upgrade pip \
    && apt-get clean

RUN pip3 --no-cache-dir install --upgrade awscli

RUN \
	#microdnf install gzip curl tar unzip git && \
	curl -Lso /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
		chmod 755 /usr/local/bin/jq && \
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && ./aws/install && \
	curl -so - https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | \
		tar xzv -C /usr/local/bin -f - oc && \
		ln -s ./oc /usr/local/bin/kubectl && \
		chmod 755 /usr/local/bin/oc 

ENV HOME /home/user
#ENV SHELL_OPERATOR_TMP_DIR tmp
ENV SHELL_OPERATOR_TMP_DIR /tmp/shell-operator
RUN mkdir /tmp/shell-operator

RUN mkdir -p /home/user
ADD bin/record_add.sh /usr/local/bin
RUN chmod -R g=u /home/user /tmp/shell-operator /usr/local/bin/record_add.sh

ADD hooks /hooks
RUN mkdir -p /hooks/tmp
RUN chmod -R g=u /hooks 
RUN chmod g=u /var/run

USER 1001


