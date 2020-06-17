.BAZELISK         := ./tools/bazelisk
.UNAME_S          := $(shell uname -s)
.BAZELISK_VERSION := 1.2.1

ifeq ($(.UNAME_S),Linux)
	.BAZELISK = ./tools/bazelisk-linux-amd64
endif
ifeq ($(.UNAME_S),Darwin)
	.BAZELISK = ./tools/bazelisk-darwin-amd64
endif

PREFIX                = ${HOME}
BAZEL_OUTPUT          = --output_base=${PREFIX}/bazel/output
BAZEL_REPOSITORY      = --repository_cache=${PREFIX}/bazel/repository_cache
BAZEL_FLAGS           = --experimental_remote_download_outputs=minimal --experimental_inmemory_jdeps_files --experimental_inmemory_dotd_files

BAZEL_BUILDKITE       = --flaky_test_attempts=3 --build_tests_only --local_test_jobs=12 --show_progress_rate_limit=5 --curses=yes --color=yes --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 --announce_rc --experimental_multi_threaded_digest --experimental_repository_cache_hardlinks --disk_cache= --sandbox_tmpfs_path=/tmp --experimental_build_event_json_file_path_conversion=false --build_event_json_file=/tmp/test_bep.json --disk_cache=${PREFIX}/bazel/cas --test_output=errors
BAZEL_BUILDKITE_BUILD = --show_progress_rate_limit=5 --curses=yes --color=yes --terminal_columns=143 --show_timestamps --verbose_failures --keep_going --jobs=32 --announce_rc --experimental_multi_threaded_digest --experimental_repository_cache_hardlinks --disk_cache= --sandbox_tmpfs_path=/tmp --disk_cache=${PREFIX}/bazel/cas
BAZEL_REMOTE          = --remote_cache=http://localhost:8080
LINUX                 = --platforms=@io_bazel_rules_go//go/toolchain:linux_amd64
INCOMPATIBLE          = --incompatible_no_rule_outputs_param=false

# Put all flags together
.BAZEL      = $(.BAZELISK) $(BAZEL_OUTPUT)

BUILD_FLAGS = $(BAZEL_REPOSITORY) $(BAZEL_FLAGS) $(BAZEL_REMOTE) $(BAZEL_BUILDKITE_BUILD)
TEST_FLAGS  = $(BAZEL_REPOSITORY) $(BAZEL_FLAGS) $(BAZEL_REMOTE) $(BAZEL_BUILDKITE)

version: ## Prints the bazel version
	@$(.BAZELISK) version
	@make separator

separator:
	@echo "-----------------------------------"

build: ## Build binaries
	@make version
	@$(.BAZEL) build $(BUILD_FLAGS) //cmd/server:server

docker: ## Build docker images
	@make version
	@$(.BAZEL) build $(BUILD_FLAGS) $(LINUX)  //cmd/server:docker

test: ## Test
	@make version
	@$(.BAZEL) build $(TEST_FLAGS) //pkg/...

gen: # Generate BUILD.bazel files
	@make version
	@$(.BAZEL) run //:gazelle -- update -exclude=protos

deps: # Add dependencies based on go.mod
	@$(.BAZEL) run $(BUILD_FLAGS) //:gazelle -- update-repos -from_file=go.mod -to_macro=repositories.bzl%go_repositories

clean:
	$(.BAZEL) clean $(BUILD_FLAGS) --expunge

ifndef WORKSPACE
define WORKSPACE
load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive",
)
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

http_archive(
    name = "io_bazel_rules_go",
    urls = [
        "https://storage.googleapis.com/bazel-mirror/github.com/bazelbuild/rules_go/releases/download/0.19.3/rules_go-0.19.3.tar.gz",
        "https://github.com/bazelbuild/rules_go/releases/download/0.19.3/rules_go-0.19.3.tar.gz",
    ],
    sha256 = "313f2c7a23fecc33023563f082f381a32b9b7254f727a7dd2d6380ccc6dfe09b",
)

load(
    "@io_bazel_rules_go//go:deps.bzl",
    "go_rules_dependencies",
    "go_register_toolchains",
)

http_archive(
    name = "bazel_gazelle",
    urls = [
        "https://storage.googleapis.com/bazel-mirror/github.com/bazelbuild/bazel-gazelle/releases/download/0.18.2/bazel-gazelle-0.18.2.tar.gz",
        "https://github.com/bazelbuild/bazel-gazelle/releases/download/0.18.2/bazel-gazelle-0.18.2.tar.gz",
    ],
    sha256 = "7fc87f4170011201b1690326e8c16c5d802836e3a0d617d8f75c3af2b23180c4",
)

load(
    "@bazel_gazelle//:deps.bzl",
    "gazelle_dependencies",
    "go_repository",
)

go_rules_dependencies()

go_register_toolchains()

gazelle_dependencies()

http_archive(
    name = "io_bazel_rules_docker",
    sha256 = "e513c0ac6534810eb7a14bf025a0f159726753f97f74ab7863c650d26e01d677",
    strip_prefix = "rules_docker-0.9.0",
    urls = ["https://github.com/bazelbuild/rules_docker/releases/download/v0.9.0/rules_docker-v0.9.0.tar.gz"],
)

load(
    "@io_bazel_rules_docker//go:image.bzl",
    _go_image_repos = "repositories",
)

_go_image_repos()

load(
    "@io_bazel_rules_docker//repositories:repositories.bzl",
    container_repositories = "repositories",
)

container_repositories()

http_archive(
    name = "io_bazel_rules_k8s",
    sha256 = "91fef3e6054096a8947289ba0b6da3cba559ecb11c851d7bdfc9ca395b46d8d8",
    strip_prefix = "rules_k8s-0.1",
    urls = ["https://github.com/bazelbuild/rules_k8s/releases/download/v0.1/rules_k8s-v0.1.tar.gz"],
)

load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_repositories")
k8s_repositories()

http_archive(
    name = "com_google_protobuf",
    strip_prefix = "protobuf-3.9.1",
    urls = ["https://github.com/google/protobuf/archive/v3.9.1.zip"],
    sha256 = "c90d9e13564c0af85fd2912545ee47b57deded6e5a97de80395b6d2d9be64854",
)

load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")

protobuf_deps()

#load("//:repositories.bzl", "go_repositories")
#go_repositories()
endef
export WORKSPACE
endif

ifndef BUILD_BAZEL
define BUILD_BAZEL
load("@bazel_gazelle//:def.bzl", "gazelle")

gazelle(
    name = "gazelle",
    prefix = "github.com/MY_ORG/MY_REPO",
)
# gazelle:exclude protos
# gazelle:proto disable
endef
export BUILD_BAZEL
endif

ifndef BAZEL_RC
define BAZEL_RC
build --host_force_python=PY2
test --host_force_python=PY2
run --host_force_python=PY2
endef

export BAZEL_RC
endif

bazelisk: # Download bazelisk
	curl -sLo tools/bazelisk-darwin-amd64 https://github.com/bazelbuild/bazelisk/releases/download/v$(.BAZELISK_VERSION)/bazelisk-darwin-amd64
	curl -sLo tools/bazelisk-linux-amd64 https://github.com/bazelbuild/bazelisk/releases/download/v$(.BAZELISK_VERSION)/bazelisk-linux-amd64
	chmod +x ./tools/bazelisk-darwin-amd64
	chmod +x ./tools/bazelisk-linux-amd64

setup: # Setup the initial files to run bazel
	@make init

init: # Generate the initial files to run bazel
	mkdir tools
	@make bazelisk
	echo "$$WORKSPACE" > WORKSPACE
	echo "$$BUILD_BAZEL" > BUILD.bazel
	echo "$$BAZEL_RC" > .bazelrc
	@make separator
	@echo "modify this line into BUILD.bazel"
	@echo '	    prefix = "github.com/MY_ORG/MY_REPO"'
