all: build

build:
	docker build --tag kiwi-jitsi-meet .

build-no-cache:
	docker build --tag kiwi-jitsi-meet --no-cache .

run:
	docker run -p 80:80 -p 443:443 -p 4443:4443 -p 10000-10100:10000-10100 -it --name kiwi-jitsi-meet kiwi-jitsi-meet

clean:
	docker container rm kiwi-jitsi-meet

export: build
	docker container rm temp-kiwi-jitsi-meet || true
	docker container create --name temp-kiwi-jitsi-meet kiwi-jitsi-meet:latest
	docker container export --output filesystem-$(shell date +%Y%m%d%H%M%S).tar temp-kiwi-jitsi-meet
	docker container rm temp-kiwi-jitsi-meet
