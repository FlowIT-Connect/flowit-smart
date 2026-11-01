FROM node:22.20.0-alpine3.22
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional && npm cache clean --force
COPY src ./src
COPY LICENSE ./
USER node
CMD ["node", "src/index.js"]
