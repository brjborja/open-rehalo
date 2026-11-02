# Self-contained image (alternative to the compose bind mount).
FROM node:22-alpine
WORKDIR /app
COPY src ./src
COPY package.json ./
ENV PORT=8730 SH2_DATA_DIR=/data
VOLUME /data
EXPOSE 8730
CMD ["node", "src/index.mjs"]
