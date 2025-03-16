SHELL := /bin/bash
.DEFAULT_GOAL := all
.SHELLFLAGS := -euo pipefail $(if $(TRACE),-x,) -c
.ONESHELL:
.DELETE_ON_ERROR:

## env ##########################################
export NAME := $(shell basename $(PWD))

## include ######################################
-include .env

## interface ####################################
all: distclean dist check build
install:
clean: destroy distclean

## workflow ######################################
distclean:
	: ## $@
	rm -rf dist

dist:
	: ## $@
	mkdir -p $@

check: docker-compose.yaml
	: ## $@
	<$^ yq -re .

build: docker-compose.yaml PLEX_CLAIM .env
	: ## $@
	cp PLEX_CLAIM .env dist
	docker compose config \
		| tee dist/docker-compose.yaml
PLEX_CLAIM: PLEX_CLAIM.dist
	: ## $@
	cp $^ $@
.env: .env.dist
	: ## $@
	cp $^ $@

install: dist/docker-compose.yaml
	: ## $@
	: ## Deploy orchestration target
	cd dist

	docker network create macvlan \
	  --driver=macvlan \
	  --opt parent=$(IFACE) \
	  --subnet=192.168.86.0/24 \
	  --gateway=192.168.86.1 \
	||:
	docker compose up -d

status:
	: ## $@
	: ## Show compose project status
	docker compose ps

## make clean
destroy: dist
	: ## $@
	: ## Remove all orchestration artifacts
	cd dist
	docker compose down --volumes --remove-orphans
