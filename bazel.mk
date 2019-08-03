.BAZELISK         := ./tools/bazelisk
.UNAME_S          := $(shell uname -s)
.BAZELISK_VERSION := 0.8.0

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

build: ## Build binaries from coupons and api packages
	@make version
	@$(.BAZEL) build $(BUILD_FLAGS) //services/traveler:traveler \

docker: ## Build docker images
	@make version
	@$(.BAZEL) build $(BUILD_FLAGS) $(LINUX)  //services/traveler:docker \

gen: # Generate BUILD.bazel files
	@make version
	@$(.BAZEL) run //:gazelle

deps: # ADd dependencies based on go.mod
	@$(.BAZEL) run $(BUILD_FLAGS) //:gazelle -- update-repos -from_file=go.mod

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
        "https://storage.googleapis.com/bazel-mirror/github.com/bazelbuild/rules_go/releases/download/0.19.1/rules_go-0.19.1.tar.gz",
        "https://github.com/bazelbuild/rules_go/releases/download/0.19.1/rules_go-0.19.1.tar.gz",
    ],
    sha256 = "8df59f11fb697743cbb3f26cfb8750395f30471e9eabde0d174c3aebc7a1cd39",
)

load(
    "@io_bazel_rules_go//go:deps.bzl",
    "go_rules_dependencies",
    "go_register_toolchains",
)

http_archive(
    name = "bazel_gazelle",
    urls = [
        "https://storage.googleapis.com/bazel-mirror/github.com/bazelbuild/bazel-gazelle/releases/download/0.18.1/bazel-gazelle-0.18.1.tar.gz",
        "https://github.com/bazelbuild/bazel-gazelle/releases/download/0.18.1/bazel-gazelle-0.18.1.tar.gz",
    ],
    sha256 = "be9296bfd64882e3c08e3283c58fcb461fa6dd3c171764fcc4cf322f60615a9b",
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
    sha256 = "87fc6a2b128147a0a3039a2fd0b53cc1f2ed5adb8716f50756544a572999ae9a",
    strip_prefix = "rules_docker-0.8.1",
    urls = ["https://github.com/bazelbuild/rules_docker/archive/v0.8.1.tar.gz"],
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

git_repository(
    name = "io_bazel_rules_k8s",
    commit = "5648b17d5f9b612cc47031a6fa961e6752fe50e8",
    remote = "https://github.com/bazelbuild/rules_k8s.git",
    shallow_since = "1564667278 -0400",
)

load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_repositories")
k8s_repositories()

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
	curl -sLo tools/bazelisk-darwin-amd64 https://github.com/bazelbuild/bazelisk/releases/download/v$(BAZELISK_VERSION)/bazelisk-darwin-amd64
	curl -sLo tools/bazelisk-linux-amd64 https://github.com/bazelbuild/bazelisk/releases/download/v$(.BAZELISK_VERSION)/bazelisk-linux-amd64

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
