CONTAINER_NAME := pihole

default:
	docker-compose down
	docker-compose up -d --build

log:
	docker logs -f $(CONTAINER_NAME)

restart:
	docker-compose stop
	docker-compose start

diagnose:
	docker exec $(CONTAINER_NAME) pihole -d

setpassword:
	docker exec $(CONTAINER_NAME) pihole -a -p
