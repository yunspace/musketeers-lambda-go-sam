BIN_DIR = bin

COMPOSE_RUN_GOLANG = docker-compose run --rm golang
COMPOSE_RUN_AWS = docker-compose run --rm aws
COMPOSE_RUN_AUTH = docker-compose run --rm gauth

STACK_NAME ?= $(ENV)-musketeers-lambda-go-sam
SAM_S3_BUCKET ?= musketeers-lambda-go-sam

# all is the default Make target. it installs the dependencies, tests, and builds the application and cleans everything.
all:
	ENVFILE=.env.example $(MAKE) test build pack clean
.PHONY: all

##################
# Public Targets #
##################

# creates .env with $(ENVFILE) if it doesn't exist already
envfile:
ifdef ENVFILE
	cp -f $(ENVFILE) .env
else
	$(MAKE) .env
endif

# creates .env with .env.template if it doesn't exist already
.env:
	cp -f .env.template .env

# deps installs all dependencies for testing/building/deploying. This example only has golang dependencies
deps: envfile
	$(COMPOSE_RUN_GOLANG) make _depsGo
.PHONY: deps

# test tests the application
test: envfile 
	$(COMPOSE_RUN_GOLANG) make _test
.PHONY: test

# build creates the SAM artifact to be deployed
build: envfile
	$(COMPOSE_RUN_GOLANG) make _build
.PHONY: build

# pack zips all binary functions individually and zip the bin dir into 1 artifact
pack: envfile
	$(COMPOSE_RUN_AWS) make _pack
.PHONY: pack

# deploy deploys the SAM artifact
deploy: envfile $(BIN_DIR)
	$(COMPOSE_RUN_AWS) make _deploy
.PHONY: deploy

# echo calls the echo API endpoint
echo: envfile
	$(COMPOSE_RUN_AWS) make _echo
.PHONY: echo

# remove removes the api gateway and the lambda
remove: envfile
	$(COMPOSE_RUN_AWS) make _remove
.PHONY: remove

# clean removes build artifacts
clean: cleanDocker
	$(COMPOSE_RUN_GOLANG) make _clean
.PHONY: clean

cleanDocker: envfile
	docker-compose down --remove-orphans
.PHONY: cleanDocker

# shellGolang let you run a shell inside a go container
shellGolang: envfile
	$(COMPOSE_RUN_GOLANG) bash
.PHONY: shellGolang

# shellServerless let you run a shell inside a serverless container
shellAWS: envfile
	$(COMPOSE_RUN_AWS) bash
.PHONY: shellAWS

auth: envfile
	$(COMPOSE_RUN_AUTH)
.PHONY: auth

###################
# Private Targets #
###################
# _test tests the go source
_test:
	go test -v ./...
.PHONY: _test

# build builds all functions individually
_build:
	@for dir in $(wildcard functions/*/) ; do \
		fxn=$$(basename $$dir) ; \
		GOOS=linux go build -ldflags="-s -w" -o $(BIN_DIR)/$$fxn functions/$$fxn/*.go ; \
#		zip -m -D $(BIN_DIR)/$$fxn.zip $(BIN_DIR)/$$fxn ; \
	done
.PHONY: _build

# _pack zips all binary functions individually and removes them
_pack:
	aws cloudformation package --template-file template.yml --s3-bucket $(SAM_S3_BUCKET) --output-template-file packaged.yml
.PHONY: _pack

# _deploy deploys the package using AWS CLI
_deploy:
	aws cloudformation deploy \
		--template-file ./packaged.yml \
		--stack-name $(STACK_NAME) \
		--capabilities CAPABILITY_IAM \
		--parameter-overrides StageName=$(ENV) EchoMessage=$(ECHO_MESSAGE)
.PHONY: _deploy

# _remove removes the aws stack
_remove:
	aws cloudformation delete-stack --stack-name $(STACK_NAME)
.PHONY: _remove

# _clean removes folders and files created when building
_clean:
	rm -rf $(GOLANG_DEPS_DIR) bin
.PHONY: _clean