FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .

# Gate: el smoke es hermético (puerto aleatorio + SQLite temporal)
RUN node test/smoke.js

ENV PORT=3000
ENV DB_PATH=/data/pixel_board.sqlite

EXPOSE 3000

CMD ["node", "server.js"]
