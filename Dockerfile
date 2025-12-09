# 1. 使用官方 Nginx 镜像
FROM nginx:latest

# 2. 将项目中的 default.conf 复制到镜像的配置目录
# 注意：这一步替代了之前在脚本里生成文件的过程
COPY default.conf /etc/nginx/conf.d/default.conf

# 3. 将 Jenkins 打包生成的静态文件复制到镜像的网页目录
COPY dist/build/h5 /usr/share/nginx/html

# 4. 暴露端口
EXPOSE 80