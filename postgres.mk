POSTGRES_VERSION := 11-alpine
MIGRATE          := command -v migrate 2> /dev/null

POSTGRES_PORT     ?= 5432
POSTGRES_USER     ?= admin
POSTGRES_PASSWORD ?= imyUNVk4cBiirCurfQCvERTnMR8GeFpj
POSTGRES_DB       ?= mydb

RDS_ADMIN_USERNAME ?=
RDS_ADMIN_PASSWORD ?=
RDS_DB_USERNAME    ?=
RDS_DB_PASSWORD    ?=
RDS_DB_NAME        ?=
RDS_HOST           ?=

.PSQL 		 := $(shell command -v psql 2> /dev/null)

# don't modify, used on dynamic eval
.COMPOSE_IDS      ?=
DEPS              ?= postgres


define PLSQL_PRIVILEGES
GRANT ALL PRIVILEGES ON DATABASE ${RDS_DB_NAME} to ${RDS_DB_USERNAME}; ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO ${RDS_DB_USERNAME}; ALTER DEFAULT PRIVILEGES GRANT ALL ON SEQUENCES TO ${RDS_DB_USERNAME}; ALTER DEFAULT PRIVILEGES GRANT ALL ON FUNCTIONS TO ${RDS_DB_USERNAME}; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
endef

define PLSQL_CREATE_DATABASE
CREATE DATABASE ${RDS_DB_NAME};
endef

define PLSQL_USER
CREATE USER ${RDS_DB_USERNAME} WITH ENCRYPTED PASSWORD '"'${RDS_DB_PASSWORD}'"';
endef

rds-create-db: ## Create database with username and privileges
	PGPASSWORD=${RDS_ADMIN_PASSWORD} psql -h ${RDS_HOST} -U${RDS_ADMIN_USERNAME} -c '$(PLSQL_CREATE_DATABASE)'
	PGPASSWORD=${RDS_ADMIN_PASSWORD} psql -h ${RDS_HOST} -U${RDS_ADMIN_USERNAME} -c '$(PLSQL_USER)'
	PGPASSWORD=${RDS_ADMIN_PASSWORD} psql -h ${RDS_HOST} -U${RDS_ADMIN_USERNAME} -d ${RDS_DB_NAME} -c '$(PLSQL_PRIVILEGES)'


define RDS_SECRETS
apiVersion: v1
kind: Secret
metadata:
  name: rds
data:
  admin_user: 
  admin_password: 
  db_name: 
  db_user: 
  db_password: 
endef
export RDS_SECRETS

rds-secrets: ## Create a template secrets.yaml
	echo "$$RDS_SECRETS" > secrets.yaml

define check-health
sleep $(1); \
all_healthy=true; \
for id in $(4); do \
	healthy=false; \
	for i in `seq -s " " $(2)`; do \
		if [[ `docker inspect --format='{{.State.Health.Status}}' $$id` == healthy ]]; then \
			healthy=true; \
			break; \
		else \
			sleep $(3); \
		fi; \
	done; \
	if [[ $$healthy == false ]]; then \
		all_healthy=false; \
		break; \
	fi; \
done; \
if [[ $$all_healthy == false ]]; then \
	false; \
fi
endef

define DOCKER_COMPOSE_POSTGRES
version: '3'
services:
    postgres:
        image: postgres:$(POSTGRES_VERSION)
        command: "postgres -c log_connections=true -c log_min_duration_statement=0"
        ports:
            - "$(POSTGRES_PORT):5432"
        environment:
            - POSTGRES_USER=$(POSTGRES_USER)
            - POSTGRES_PASSWORD=$(POSTGRES_PASSWORD)
            - POSTGRES_DB=$(POSTGRES_DB)
        healthcheck:
          test: pg_isready -p 5432 -d $(POSTGRES_DB) -U $(POSTGRES_USER)
          interval: 1s
          timeout: 1s
          retries: 10
endef
export DOCKER_COMPOSE_POSTGRES

pg-compose-start:
	@echo "$$DOCKER_COMPOSE_POSTGRES" > .docker-compose.yml
	docker-compose -f .docker-compose.yml up -d

pg-compose-stop:
	@echo "$$DOCKER_COMPOSE_POSTGRES" > .docker-compose.yml
	docker-compose -f .docker-compose.yml stop
	yes | docker-compose -f .docker-compose.yml rm

compose-ids:
	$(eval .COMPOSE_IDS := $(shell docker-compose -f .docker-compose.yml ps -q $(DEPS)))

postgres-health: | compose-ids
	$(call check-health, 3, 10, 1, $(.COMPOSE_IDS))

check-migrate:
ifndef MIGRATE
	GO111MODULE=off go get -tags 'postgres' -u github.com/golang-migrate/migrate/cmd/migrate
endif

base-schema: ## Create a database with the base schema
	@$(MAKE) base-impl
base-impl: | check-migrate pg-compose-stop pg-compose-start pg-compose-start postgres-health
	migrate -path $(shell pwd)/scripts/db -database "postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:$(POSTGRES_PORT)/$(POSTGRES_DB)?sslmode=disable" up

check-migrations: ## Checks if the migrations can run in postgres
	@$(MAKE) check-migrations-impl
check-migrations-impl: | check-migrate pg-compose-stop pg-compose-start pg-compose-start postgres-health migrate

migrate: ## Run available migrations
	@$(MAKE) check-migrate
	migrate -path $(shell pwd)/scripts/db/migrations -database "postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:$(POSTGRES_PORT)/$(POSTGRES_DB)?sslmode=disable" up

