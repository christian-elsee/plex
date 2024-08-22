.DEFAULT_GOAL := all
.SHELLFLAGS := -euo pipefail $(if $(TRACE),-x,) -c
.ONESHELL:
.DELETE_ON_ERROR:

## env ##########################################
export NAME := $(shell basename $(PWD))

## interface ####################################
all: distclean dist build check
install: install/plex install/test
init: init/secret init/helm values.yaml
clean: delete distclean

## workflow #####################################
distclean:
	: ## $@
	rm -rf dist

dist:
	: ## $@
	mkdir -p $@

build: export CLAIM = $(shell cat secret/CLAIM)
build:
	: ## $@
	tail -n +1 manifest/* \
		| sed -E -- 's/^.+\=$$/---/' \
		| envsubst \
		| tee dist/manifest.yaml
	<values.yaml envsubst \
		| tee dist/values.yaml

	helm template "$(NAME)" plex/plex-media-server \
		--namespace "$(NAME)" \
		--dry-run=client \
		--values dist/values.yaml \
	| tee dist/chart.yaml

check: dist/manifest.yaml
	: ## $@
	# validate configuration using migrate command
	kubectl apply \
		--dry-run=client \
		-f $<
	helm upgrade --install "$(NAME)" plex/plex-media-server \
		--namespace "$(NAME)" \
		--dry-run=client 

install/plex: dist/manifest.yaml
	: ## $@
	kubectl apply -f manifest/namespace.yaml
	kubectl apply -f $< --namespace "$(NAME)"
	helm upgrade --install "$(NAME)" plex/plex-media-server \
		--namespace "$(NAME)" 

install/test:
	: ## $@
	# sanity check install
	helm status "$(NAME)" -n "$(NAME)"

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

init/secret: secret
secret:
	: ## $@
	mkdir $@
	touch $@/CLAIM

init/helm:
	: ## $@
	helm repo add "$(NAME)" \
		https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages
values.yaml:
	: ## $@
	helm show values plex/plex-media-server | tee $@
