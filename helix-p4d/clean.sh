docker rm -f $(docker ps -a -q) 
docker rmi $(docker images -f "dangling=true" -q)
docker volume rm $(docker volume ls -q)
docker images
ls -lh ~/Library/Containers/com.docker.docker/Data/com.docker.driver.amd64-linux/Docker.qcow2
