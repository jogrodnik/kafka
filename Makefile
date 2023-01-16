SHELL:=/bin/bash

build: build-alpine build-jdk6  build-jdk8

build-alpine:
	cd docker-images/alpine && docker build -t prk.devops/alpine:3.5 .
build-jdk6:
	cd docker-images/jdk && docker build -f Dockerfile6  -t prk.devops/jdk:6 .
build-jdk8:
	cd docker-images/jdk && docker build -f Dockerfile8  -t prk.devops/jdk:8 .
vagrant: build

https://gist.github.com/SmartFinn/7bb86b078726f0763ce0