FROM node:22.16.0-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev --ignore-scripts
COPY src ./src
COPY dump.js .
ENTRYPOINT ["node", "dump.js"]
