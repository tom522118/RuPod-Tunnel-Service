#!/bin/bash
sudo docker run -d \
  --name my-nginx \
  -p 80:80 \
  --restart always \
  nginx
