CONTAINER_NAME := pihole

default:
	docker-compose down
	docker-compose up -d --build

log:
	docker logs -f $(CONTAINER_NAME)

restart:
	docker-compose stop
	docker-compose start

getpassword:
	docker exec $(CONTAINER_NAME) sh -c 'echo $$WEBPASSWORD'

diagnose:
	docker exec $(CONTAINER_NAME) pihole -d

secret:
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1

flush:
	docker exec $(CONTAINER_NAME) pihole flush
