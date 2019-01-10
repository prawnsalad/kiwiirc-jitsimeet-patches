FROM debian:9.5

ENV DEBIAN_FRONTEND noninteractive

# TODO: move these values from buildtime to runtime
ENV JITSI_MEET_DOMAIN jitsi.192.168.1.144.xip.io
ENV JITSI_MEET_APPID 192.168.1.122
ENV JITSI_MEET_APPSECRET kiwisecret

ENV EXTERNAL_IP 192.168.1.144

RUN apt-get update \
    && apt-get -y -q install wget gnupg apt-transport-https lsb-release apt-utils git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN echo 'deb https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list
RUN wget -qO -  https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -

RUN echo deb http://packages.prosody.im/debian $(lsb_release -sc) main | tee /etc/apt/sources.list.d/prosody-trunk.list
RUN wget -qO - https://prosody.im/files/prosody-debian-packages.key | apt-key add -

# install nginx first so jitsi packages configure a site automatically
RUN apt-get update \
    && apt-get -y -q install nginx \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# workaround luacrypto build failure
RUN apt-get update \
    && apt-get -y -q install libssl1.0-dev luarocks \
    && apt-get clean \
    && luarocks install luacrypto \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# set debconf selections
RUN echo jitsi-meet-web-config jitsi-meet/cert-choice select "Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)" | debconf-set-selections && \
    echo jitsi-meet-tokens jitsi-meet-tokens/appid string $JITSI_MEET_APPID | debconf-set-selections && \
    echo jitsi-meet-tokens jitsi-meet-tokens/appsecret password $JITSI_MEET_APPSECRET | debconf-set-selections && \
    echo jitsi-videobridge jitsi-videobridge/jvb-hostname string $JITSI_MEET_DOMAIN | debconf-set-selections

# install jitsi-meet packages
RUN apt-get update \
    && apt-get install -y jitsi-meet jitsi-meet-tokens \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# apply jitsi-meet's prosody patches
RUN patch -N /usr/lib/prosody/modules/mod_bosh.lua /usr/share/jitsi-meet/prosody-plugins/mod_bosh.lua.patch

# edit configs
ADD ./patches/ /opt/local/config-patches
RUN cd /etc/prosody/conf.avail/ && sed "s/PLACEHOLDER_JITSI_MEET_DOMAIN/$JITSI_MEET_DOMAIN/g" /opt/local/config-patches/prosody-site.patch | patch -p1
RUN cd /etc/jitsi/jicofo && patch -p1 < /opt/local/config-patches/jicofo-sip-communicator-properties.patch
RUN cd /etc/jitsi/meet/ && sed "s/PLACEHOLDER_JITSI_MEET_DOMAIN/$JITSI_MEET_DOMAIN/g" /opt/local/config-patches/jitsi-meet-config.patch | patch -p1

# apply kiwiirc's jitsi-meet patches
RUN git clone https://github.com/kiwiirc/jitsimeet-patches /opt/local/kiwiirc-jitsimeet-patches && cd /opt/local/kiwiirc-jitsimeet-patches && ./patch_jitsi-meet-tokens_for_kiwi.sh

EXPOSE 80 443 4443 10000-10100

VOLUME [ "/sys/fs/cgroup" ]

RUN echo "org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$EXTERNAL_IP" >> /etc/jitsi/videobridge/sip-communicator.properties

CMD echo "org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=$(ip -br addr show dev eth0|awk '{print $3}'|cut -d'/' -f1)" >> /etc/jitsi/videobridge/sip-communicator.properties \
    && service prosody start \
    && service jicofo start \
    && service jitsi-videobridge start \
    && service nginx start \
    && bash
