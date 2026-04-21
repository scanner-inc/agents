FROM node:22-slim

WORKDIR /home/agent/app

COPY package.json package-lock.json ./
RUN npm ci --production

COPY dist/ ./

# The agent SDK spawns cli.js as a child process, which needs a writable HOME
RUN mkdir -p /home/agent && chown node:node /home/agent
ENV HOME=/home/agent

USER node

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f "node threat_hunt" || exit 1

ENTRYPOINT ["node", "threat_hunt.js"]
