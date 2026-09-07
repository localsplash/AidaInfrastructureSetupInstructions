FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
COPY test ./test
COPY simulators ./simulators
COPY prompts ./prompts
COPY asterisk ./asterisk
COPY deploy ./deploy
RUN npm run verify
RUN npm run build
