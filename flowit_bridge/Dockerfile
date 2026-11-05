# Construit sur la box Home Assistant à l'installation : récupère bridge/ et yeedi/ depuis GitHub.
# yeedi/ (licence GPL) reste un programme séparé, lancé à côté de la passerelle si un compte
# yeedi est renseigné dans les options.
ARG BUILD_FROM
FROM node:22.20.0-alpine3.22
ARG FLOWIT_REF=main
ENV NODE_ENV=production
WORKDIR /app
ADD https://codeload.github.com/flowit-connect/flowit-smart/tar.gz/refs/heads/${FLOWIT_REF} /tmp/flowit.tar.gz
RUN tar -xzf /tmp/flowit.tar.gz --strip-components=2 "flowit-smart-${FLOWIT_REF}/bridge" \
  && mkdir /yeedi && tar -xzf /tmp/flowit.tar.gz -C /yeedi --strip-components=2 "flowit-smart-${FLOWIT_REF}/yeedi" \
  && rm /tmp/flowit.tar.gz \
  && npm ci --omit=dev && (cd /yeedi && npm ci --omit=dev --omit=optional) && npm cache clean --force
CMD ["node", "src/index.js"]
