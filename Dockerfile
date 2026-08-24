# ---------------------------------------------------
# Sabin Shrestha Portfolio — production image
# Static site served by nginx (multi-stage keeps the
# final image tiny and free of any build tooling).
# ---------------------------------------------------

FROM nginx:1.27-alpine AS runtime

# Remove default nginx site content & config
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/default.conf

# Custom server config (gzip, cache headers, healthcheck)
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# Site files
COPY index.html /usr/share/nginx/html/index.html
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/
COPY assets/ /usr/share/nginx/html/assets/

# Run as the existing unprivileged nginx user
RUN chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
