SHELL := /bin/bash
.DEFAULT_GOAL := all
.SHELLFLAGS := -euo pipefail $(if $(TRACE),-x,) -c
.ONESHELL:
.DELETE_ON_ERROR:

## env ##########################################
export NAME := $(shell basename $(PWD))

## interface ####################################
all: distclean dist build check
install: install/plex post-install
init: init/secret init/helm values.yaml
clean: delete distclean

## workflow ######################################
## make [all]
distclean:
	: ## $@
	rm -rf dist

dist:
	: ## $@
	mkdir -p $@

build: secret/PLEX_CLAIM values.yaml
	: ## $@
	tail -n +1 manifest/* \
		| sed -E -- 's/^.+\=$$/---/' \
		| tee dist/manifest.yaml

	helm template "$(NAME)" plex/plex-media-server \
		--namespace "$(NAME)" \
		--create-namespace \
		--values values.yaml \
		--set "extraEnv.PLEX_CLAIM=$(shell cat $<)" \
		--dry-run=client \
	| tee dist/chart.yaml

check: secret/PLEX_CLAIM dist/manifest.yaml values.yaml
	: ## $@
	kubectl apply \
		--dry-run=client \
		-f dist/manifest.yaml

	helm upgrade "$(NAME)" plex/plex-media-server \
		--install \
		--namespace "$(NAME)" \
		--create-namespace \
		--values values.yaml \
		--set "extraEnv.PLEX_CLAIM=$(shell cat secret/PLEX_CLAIM)" \
		--dry-run=client

## make install
install/plex: dist/manifest.yaml secret/PLEX_CLAIM
	: ## $@
	kubectl apply -f manifest/namespace.yaml
	kubectl apply -f dist/manifest.yaml --namespace "$(NAME)"

	helm upgrade "$(NAME)" plex/plex-media-server \
		--install \
		--namespace "$(NAME)" \
		--create-namespace \
		--values values.yaml \
		--set "extraEnv.PLEX_CLAIM=$(shell cat secret/PLEX_CLAIM)" \

post-install:
	: ## $@
	# sanity check install
	helm status "$(NAME)" -n "$(NAME)"
	helm get values "$(NAME)" -n "$(NAME)" \
		| tee dist/values.yaml

## make clean
delete:
	: ## $@
	helm delete $(NAME) \
		-n $(NAME) \
		--debug \
		--no-hooks \
		--ignore-not-found \
		--cascade=foreground \
	||:
	kubectl delete namespace $(NAME) --wait --cascade=foreground \
	||:

## make init
init/secret: secret secret/PLEX_CLAIM
secret:
	: ## $@
	mkdir $@
secret/PLEX_CLAIM:
	: ## $@
	touch $@

init/helm:
	: ## $@
	helm repo add "$(NAME)" \
		https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages

values.yaml:
	: ## $@
	helm show values plex/plex-media-server | tee $@
