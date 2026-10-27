# Construit sur la box Home Assistant à l'installation : récupère bridge/ depuis GitHub.
ARG BUILD_FROM
FROM node:22.20.0-alpine3.22
ARG FLOWIT_REF=main
ENV NODE_ENV=production
WORKDIR /app
ADD https://codeload.github.com/flowit-connect/flowit-smart/tar.gz/refs/heads/${FLOWIT_REF} /tmp/flowit.tar.gz
RUN tar -xzf /tmp/flowit.tar.gz --strip-components=2 "flowit-smart-${FLOWIT_REF}/bridge" \
  && rm /tmp/flowit.tar.gz \
  && npm ci --omit=dev && npm cache clean --force
CMD ["node", "src/index.js"]
