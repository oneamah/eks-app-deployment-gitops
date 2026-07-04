FROM node:22-alpine AS build
WORKDIR /app

COPY app/package*.json ./
RUN npm install

COPY app/ ./
RUN npm run build

FROM nginx:1.27-alpine
RUN apk add --no-cache gettext

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/app/browser /usr/share/nginx/html
COPY env.template.js /usr/share/nginx/html/env.template.js
COPY docker-entrypoint-env.sh /docker-entrypoint.d/40-env.sh
RUN chmod +x /docker-entrypoint.d/40-env.sh

EXPOSE 80
