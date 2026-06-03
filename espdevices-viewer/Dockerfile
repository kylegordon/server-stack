FROM nginx:alpine

# Copy the HTML file to nginx's default serve directory
COPY index.html /usr/share/nginx/html/

# Expose port 80
EXPOSE 80

# nginx alpine image already has a proper entrypoint, so no need to specify CMD
