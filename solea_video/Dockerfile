# Construit sur la box Home Assistant à l'installation : récupère bridge/ depuis GitHub et le
# relais vidéo MediaMTX (logiciel libre, MIT) pour le processeur de la box.
ARG BUILD_FROM
FROM node:22.20.0-alpine3.22
ARG BUILD_ARCH=amd64
ARG FLOWIT_REF=main
ARG MTX_VERSION=v1.21.3
ENV NODE_ENV=production
WORKDIR /app
ADD https://codeload.github.com/flowit-connect/flowit-smart/tar.gz/refs/heads/${FLOWIT_REF} /tmp/flowit.tar.gz
RUN tar -xzf /tmp/flowit.tar.gz --strip-components=2 "flowit-smart-${FLOWIT_REF}/bridge" \
  && tar -xzf /tmp/flowit.tar.gz -C / --strip-components=2 "flowit-smart-${FLOWIT_REF}/solea_video/run_video.sh" \
  && rm /tmp/flowit.tar.gz \
  && npm ci --omit=dev && npm cache clean --force \
  && case "${BUILD_ARCH}" in aarch64) MTX_ARCH=arm64 ;; *) MTX_ARCH=amd64 ;; esac \
  && mkdir -p /mediamtx \
  && node -e "fetch(process.argv[1]).then(async(r)=>{if(!r.ok)throw new Error('HTTP '+r.status);process.stdout.write(Buffer.from(await r.arrayBuffer()))}).catch((e)=>{console.error(e.message);process.exit(1)})" \
       "https://github.com/bluenviron/mediamtx/releases/download/${MTX_VERSION}/mediamtx_${MTX_VERSION}_linux_${MTX_ARCH}.tar.gz" > /tmp/mtx.tar.gz \
  && tar -xzf /tmp/mtx.tar.gz -C /mediamtx mediamtx && rm /tmp/mtx.tar.gz \
  && sed -i 's/^logDestinations:.*/logDestinations: [stdout]/' config/mediamtx.yml \
  && chmod +x /run_video.sh /mediamtx/mediamtx
CMD ["/run_video.sh"]
