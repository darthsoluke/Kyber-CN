FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget gnupg2 winbind xvfb ca-certificates tar xz-utils unzip lib32gcc-s1 lib32stdc++6 libc6-i386

RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-devel

WORKDIR /home/kyber

RUN wget -O wine-ge-custom.tar.xz https://github.com/GloriousEggroll/wine-ge-custom/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz && \
    mkdir -p /home/kyber/wine && \
    tar -xf wine-ge-custom.tar.xz -C /home/kyber/wine --strip-components=1 && \
    rm wine-ge-custom.tar.xz

WORKDIR /home/kyber

RUN mkdir -p /root/.local/share/maxima/wine/prefix

COPY entrypoint.sh /opt/kyber/entrypoint.sh
RUN chmod +x /opt/kyber/entrypoint.sh && \
    sed -i -e 's/\r$//' /opt/kyber/entrypoint.sh

COPY _work/kyber_cli /opt/kyber/kyber_cli
COPY _work/librust_lib.so /opt/kyber/librust_lib.so

COPY _work/maxima-bootstrap /opt/kyber/maxima-bootstrap
COPY _work/wine-helper.exe /opt/kyber/wine-helper.exe

RUN chmod +x /opt/kyber/kyber_cli && \
    chmod +x /opt/kyber/maxima-bootstrap && \
    chmod +x /opt/kyber/wine-helper.exe

COPY _work/VanillaBundleAggregation.kb /root/.local/share/kyber/module/VanillaBundleAggregation.kb
COPY _work/vivoxsdk.dll /root/.local/share/kyber/module/vivoxsdk.dll
COPY _work/ca_root.pem /root/.local/share/kyber/module/ca_root.pem
COPY _work/Kyber.dll /root/.local/share/kyber/module/Kyber.dll
    
EXPOSE 25200/udp

ENV MAXIMA_DISABLE_WINE_VERIFICATION=1
ENV MAXIMA_WINE_COMMAND="/home/kyber/wine/bin/wine64"
ENV MAXIMA_DISABLE_QRC=1

# Fixed container paths. The entrypoint validates these before starting.
ENV KYBER_GAME_PATH=/mnt/battlefront/starwarsbattlefrontii.exe
ENV KYBER_MODULE_DIR=/root/.local/share/kyber/module

# This must be set by the runner in the form of persona:password
ENV MAXIMA_CREDENTIALS=

# This must be set by the runner as a kyber account token, retrieved from `kyber_cli get_token`
ENV KYBER_TOKEN=

ENV KYBER_SERVER_NAME=
ENV KYBER_SERVER_MAP=
ENV KYBER_SERVER_MODE=
ENV KYBER_SERVER_PORT=
ENV KYBER_SERVER_MAX_PLAYERS=

WORKDIR /opt/kyber
ENTRYPOINT ["/opt/kyber/entrypoint.sh"]
