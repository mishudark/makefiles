-include project.mk

export GOPATH  := $(HOME)
export GOBIN   := $(GOPATH)/bin
export PATH    := $(GOBIN):$(PATH)
export GOPROXY := https://goproxy.io

GO_MAIN_PATH        ?= ./cmd
IMAGE_ENABLE        ?= false
IMAGE_BASE          ?= golang:alpine
GO_BUILD_FLAGS      ?= -ldflags "-d -s -w" -tags netgo -installsuffix netgo
PACKAGE_TIMESTAMP   ?= $(shell git log -1 --format=%h)
PUBLISH             ?= false
DOCKER_PUBLISH_URL  ?=
DOCKER_PUBLISH_USER ?=
DOCKER_PUBLISH_PWD  ?=
DOCKER_PUBLISH_TAG  ?=
LINT_VERSION        ?= v1.17.1

GO_MOD_CACHE      := /go/pkg/mod

GO                := $(shell command -v go 2> /dev/null)
DOCKER            := $(shell command -v docker 2> /dev/null)
LINTER            := $(shell command -v golangci-lint 2> /dev/null)
MOQ               := $(shell command -v moq 2> /dev/null)


.GOMODFILE        := go.mod
.GIT              := .git
.CACHE            := .cache
.PROJECT_MK       := project.mk
.SERVER_NAME      := .server.build

check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))


ifndef PACKAGE_TIMESTAMP
ifeq ($(.GIT),$(wildcard $(.GIT)))
PACKAGE_TIMESTAMP = $(shell git rev-list --max-count=1 --timestamp HEAD | awk '{print $$1}')
endif
endif

define PROJECT_TRAVIS
language: go

go:
- 1.12.x

script:
  - make lint
  - make test
  - make image-static
endef
export PROJECT_TRAVIS

define PROJECT_MK_CONTENT
SERVICES  := ingestor scheduler
IMAGE_ENABLE := false
PUBLISH := false

DOCKER_PUBLISH_URL =
DOCKER_PUBLISH_USER =
DOCKER_PUBLISH_PWD =
endef
export PROJECT_MK_CONTENT

init:
ifneq ($(.PROJECT_MK),$(wildcard $(.PROJECT_MK)))
	@echo "$$PROJECT_MK_CONTENT" > project.mk
	@echo "$$PROJECT_TRAVIS" > .travis.yml
	$(info project.mk has been created, please review the config there)
	$(info .travis.yml has been created, please configure your CI)
	exit 1
else
	$(call check_defined, GO_MAIN_PATH, path to the main.go package required on project.mk)
endif

ifeq ($(IMAGE_ENABLE), true)
$(call check_defined, DOCKER, please install docker)
endif

#ifeq ($(IMAGE_ENABLE), false)
$(call check_defined, GO, go is required to perform this operation)
#endif

ifeq ($(PUBLISH),true)
$(call check_defined, DOCKER_PUBLISH_URL, docker registry url required)
$(call check_defined, DOCKER_PUBLISH_USER, docker username for registry required)
$(call check_defined, DOCKER_PUBLISH_PWD, docker password for registry required)
endif

define IMAGE_FAST
FROM alpine:latest
RUN apk --no-cache add ca-certificates
RUN adduser -S -D -H -h /app appuser
USER appuser
WORKDIR /go/bin
COPY $(.SERVER_NAME) .
CMD ["./$(.SERVER_NAME)"]
endef
export IMAGE_FAST

docker: ## Docker image for every service listed in project.mk
	@echo "$$IMAGE_FAST" > .Dockerfile
	@$(foreach svc,$(SERVICES), \
		echo "------------------------" && \
		echo "Building binary: $(GO_MAIN_PATH)/$(svc) ..." && \
		GO111MODULE=on CGO_ENABLED=0 GOOS=linux go build $(GO_BUILD_FLAGS) -o $(.SERVER_NAME) $(GO_MAIN_PATH)/$(svc)	&& \
		docker build -t $(svc) -f .Dockerfile . &&) true

check-linter:
ifndef LINTER
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(shell go env GOPATH)/bin $(LINT_VERSION)
endif

lint: ## Lint with the standard options
	@make lint-impl
lint-impl: |init check-linter
	GO111MODULE=on golangci-lint run

gomod:
ifneq ($(.GOMODFILE),$(wildcard $(.GOMODFILE)))
$(error go.mod is required)
endif

local-test: |init
	GO111MODULE=on CGO_ENABLED=0 go test ./...

cache:
ifneq ($(.CACHE),$(wildcard $(.CACHE)))
	mkdir $(.CACHE)
	touch $(.CACHE)/empty
endif

ifeq ($(IMAGE_ENABLE), true)
endif

ifeq ($(IMAGE_ENABLE), false)
build: ## Build the project
	@make build-impl
build-impl: |init gomod
	@$(foreach svc,$(SERVICES), \
		echo "------------------------" && \
		echo "Building $(svc) ..." && \
		GO111MODULE=on CGO_ENABLED=0 GOOS=linux go build $(GO_BUILD_FLAGS) -o $(svc) $(GO_MAIN_PATH)/$(svc)	&&) true

test: ## Run tests under pkg directory
	@make local-test

.PHONY: vendor
vendor: ## Download the dependencies
vendor-impl: |gomod
	GO111MODULE=on go mod download
endif

publish: ## Publish a container to a docker registry [PUBLISH is required]
	@docker login -u $(DOCKER_PUBLISH_USER) -p $(DOCKER_PUBLISH_PWD) $(DOCKER_PUBLISH_URL)
	@$(foreach svc,$(SERVICES), \
		echo "------------------------" && \
		echo "Publishing $(svc):$(PACKAGE_TIMESTAMP) ..." && \
		docker tag $(shell docker images -q $(svc)) $(DOCKER_PUBLISH_URL)/$(svc):$(PACKAGE_TIMESTAMP) && \
		docker push $(DOCKER_PUBLISH_URL)/$(svc):$(PACKAGE_TIMESTAMP) &&) true

check-moq:
ifndef MOQ
	GO111MODULE=off go get github.com/matryer/moq
endif
