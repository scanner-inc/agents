FROM public.ecr.aws/lambda/nodejs:22

# The agent SDK spawns cli.js as a child process, which needs a writable HOME
ENV HOME=/tmp

COPY package.json package-lock.json ./
RUN npm ci --production

COPY dist/ ./dist/

CMD ["dist/handler.handler"]
