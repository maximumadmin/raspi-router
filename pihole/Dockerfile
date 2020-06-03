FROM pihole/pihole:v5.0-armhf

RUN apt-get update &&\
    apt-get install -y python3 &&\
    apt-get clean

COPY ftl-flush.py /usr/local/bin/ftl-flush
RUN chmod +x /usr/local/bin/ftl-flush
